package main

import (
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"time"

	"github.com/Pigmassacre/smb3-gimmick/internal/build"
)

//go:embed page.html
var page embed.FS

var version = "dev"

func main() {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		fmt.Fprintln(os.Stderr, "The program could not start.")
		os.Exit(1)
	}
	addr := ln.Addr().String()
	url := "http://" + addr + "/"

	mux := http.NewServeMux()
	mux.HandleFunc("/", servePage)
	mux.HandleFunc("/check", serveCheck)
	mux.HandleFunc("/build", serveBuild)
	mux.HandleFunc("/bye", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || !fromHere(r) {
			http.NotFound(w, r)
			return
		}
		w.WriteHeader(http.StatusNoContent)
		go func() {
			time.Sleep(150 * time.Millisecond)
			os.Exit(0)
		}()
	})

	fmt.Printf("SMB3 Gimmick %s\n", version)
	fmt.Println()
	fmt.Println("A page should have opened in your web browser.")
	fmt.Println("If it didn't, open this address:")
	fmt.Println()
	fmt.Println("  " + url)
	fmt.Println()
	fmt.Println("Leave this window open while you use it.")
	fmt.Println("Close this window when you are done.")

	go func() {
		time.Sleep(200 * time.Millisecond)
		openBrowser(url)
	}()

	srv := &http.Server{Handler: mux}
	if err := srv.Serve(ln); err != nil && err != http.ErrServerClosed {
		fmt.Fprintln(os.Stderr, "The program stopped.")
		os.Exit(1)
	}
}

func servePage(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/favicon.ico" {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	f, err := page.Open("page.html")
	if err != nil {
		http.Error(w, "missing page", http.StatusInternalServerError)
		return
	}
	defer f.Close()
	io.Copy(w, f)
}

func serveCheck(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost || !fromHere(r) {
		http.NotFound(w, r)
		return
	}
	data, err := oneFile(r, "file")
	if err != nil {
		writeJSON(w, http.StatusBadRequest, build.Game{Message: "Choose a game file and try again."})
		return
	}
	writeJSON(w, http.StatusOK, build.Recognize(data))
}

func serveBuild(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost || !fromHere(r) {
		http.NotFound(w, r)
		return
	}
	smb, err := oneFile(r, "smb3")
	if err != nil {
		writeJSON(w, http.StatusBadRequest, build.Game{Message: "Choose Super Mario Bros. 3 and try again."})
		return
	}
	gim, err := oneFile(r, "gimmick")
	if err != nil {
		writeJSON(w, http.StatusBadRequest, build.Game{Message: "Choose Gimmick! and try again."})
		return
	}
	out, err := build.Build(smb, gim)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, build.Game{Message: err.Error()})
		return
	}
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Disposition", `attachment; filename="SMB3 Gimmick.nes"`)
	w.Header().Set("Cache-Control", "no-store")
	w.Write(out)
}

func oneFile(r *http.Request, field string) ([]byte, error) {
	r.Body = http.MaxBytesReader(nil, r.Body, 2<<20)
	if err := r.ParseMultipartForm(2 << 20); err != nil {
		return nil, err
	}
	f, _, err := r.FormFile(field)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return io.ReadAll(io.LimitReader(f, 1<<20+512))
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

func fromHere(r *http.Request) bool {
	host := r.Host
	if h, _, err := net.SplitHostPort(r.Host); err == nil {
		host = h
	}
	if host != "127.0.0.1" && host != "localhost" {
		return false
	}
	origin := r.Header.Get("Origin")
	if origin == "" {
		return true
	}
	return origin == "http://"+r.Host || origin == "http://127.0.0.1" || origin == "http://localhost"
}

func openBrowser(url string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", url)
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	default:
		cmd = exec.Command("xdg-open", url)
	}
	_ = cmd.Start()
}
