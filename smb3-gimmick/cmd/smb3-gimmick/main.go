package main

import (
	_ "embed"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sync"
	"unsafe"

	"github.com/AllenDang/cimgui-go/imgui"
	g "github.com/AllenDang/giu"
	"github.com/ncruces/zenity"

	"github.com/Pigmassacre/smb3-gimmick/internal/build"
)

//go:embed fonts/NotoSans-Regular.ttf
var regularFont []byte

//go:embed fonts/NotoSans-SemiBold.ttf
var boldFont []byte

var version = "dev"

const outName = "SMB3 Gimmick.nes"

var (
	ink       = rgb(0x2c2622)
	muted     = rgb(0x6d645c)
	paper     = rgb(0xf6f1e8)
	card      = rgb(0xfffdf8)
	line      = rgb(0xe4d9c8)
	green     = rgb(0x1f7a45)
	greenDark = rgb(0x166237)
	soft      = rgb(0xe7f5ec)
	softLine  = rgb(0xb7dfc6)
	warnBg    = rgb(0xfdecea)
	warn      = rgb(0x8d2e2e)
	fileBtn   = rgb(0xefe7da)
	fileHover = rgb(0xe6dccb)
	white     = rgb(0xffffff)
)

type game struct {
	path string
	data []byte
}

var (
	mu      sync.Mutex
	smb3    game
	gimmick game
	problem string
	busy    bool
	savedTo string

	regular *imgui.Font
	bold    *imgui.Font
	scale   float32
	width   float32
	dialogs = zenity.IsAvailable()
)

func rgb(c uint32) imgui.Vec4 {
	return imgui.Vec4{
		X: float32(c>>16&0xff) / 255,
		Y: float32(c>>8&0xff) / 255,
		Z: float32(c&0xff) / 255,
		W: 1,
	}
}

func main() {
	wnd := g.NewMasterWindow("SMB3 Gimmick", 620, 680, 0)
	wnd.SetStyle(nil)
	wnd.SetBgColor(g.Vec4ToRGBA(paper))
	wnd.SetDropCallback(take)

	style := imgui.CurrentStyle()
	scale = style.FontScaleDpi()
	wnd.SetSizeLimits(int(460*scale), int(560*scale), -1, -1)

	imgui.StyleColorsLight()
	colors := style.Colors()
	colors[imgui.ColText] = ink
	colors[imgui.ColTextDisabled] = muted
	colors[imgui.ColWindowBg] = paper
	colors[imgui.ColChildBg] = card
	colors[imgui.ColBorder] = line
	colors[imgui.ColButton] = fileBtn
	colors[imgui.ColButtonHovered] = fileHover
	colors[imgui.ColButtonActive] = fileHover
	colors[imgui.ColScrollbarBg] = paper
	style.SetColors(&colors)
	style.SetWindowPadding(imgui.Vec2{X: 28 * scale, Y: 28 * scale})
	style.SetFramePadding(imgui.Vec2{X: 18 * scale, Y: 10 * scale})
	style.SetItemSpacing(imgui.Vec2{X: 10 * scale, Y: 12 * scale})
	style.SetFrameRounding(999)
	style.SetChildRounding(14 * scale)
	style.SetChildBorderSize(1.5 * scale)
	style.SetWindowBorderSize(0)
	style.SetDisabledAlpha(1)

	take(os.Args[1:])
	wnd.Run(loop)
}

func take(paths []string) {
	mu.Lock()
	defer mu.Unlock()
	problem = ""
	for _, p := range paths {
		p, _ = filepath.Abs(p)
		data, err := readGame(p)
		if err != nil {
			problem = "That file could not be opened: " + filepath.Base(p)
			continue
		}
		info := build.Recognize(data)
		if !info.OK {
			problem = info.Message
			continue
		}
		savedTo = ""
		if info.Role == "smb3" {
			smb3 = game{path: p, data: data}
		} else {
			gimmick = game{path: p, data: data}
		}
	}
	g.Update()
}

func readGame(path string) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return io.ReadAll(io.LimitReader(f, 1<<20+512))
}

func choose() {
	paths, err := zenity.SelectFileMultiple(
		zenity.Title("Choose the game files"),
		zenity.FileFilter{Name: "NES games", Patterns: []string{"*.nes"}, CaseFold: true},
	)
	mu.Lock()
	busy = false
	if err != nil && !errors.Is(err, zenity.ErrCanceled) {
		problem = "The file chooser could not open. Drop the game files on this window instead."
	}
	mu.Unlock()
	if err == nil {
		take(paths)
	}
	g.Update()
}

func makeGame(smb, gim []byte, path string) {
	if dialogs {
		p, err := zenity.SelectFileSave(
			zenity.Title("Save the game"),
			zenity.Filename(path),
			zenity.ConfirmOverwrite(),
			zenity.FileFilter{Name: "NES games", Patterns: []string{"*.nes"}, CaseFold: true},
		)
		if err != nil {
			mu.Lock()
			busy = false
			if !errors.Is(err, zenity.ErrCanceled) {
				problem = "The save window could not open. Please try again."
			}
			mu.Unlock()
			g.Update()
			return
		}
		path = p
		if filepath.Ext(path) == "" {
			path += ".nes"
		}
	}

	out, err := build.Build(smb, gim)
	msg := ""
	if err != nil {
		msg = err.Error()
	} else if err := os.WriteFile(path, out, 0o644); err != nil {
		msg = "The game could not be saved in " + filepath.Dir(path) + ". Please choose another folder."
	}

	mu.Lock()
	busy = false
	problem = msg
	if msg == "" {
		savedTo = path
	}
	mu.Unlock()
	g.Update()
}

func reveal(path string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("explorer", "/select,", path)
	case "darwin":
		cmd = exec.Command("open", "-R", path)
	default:
		cmd = exec.Command("xdg-open", filepath.Dir(path))
	}
	_ = cmd.Start()
}

func loop() {
	mu.Lock()
	defer mu.Unlock()

	// giu may build its font atlas before main gets to add fonts, so they are added on the first frame instead.
	if regular == nil {
		regular = addFont(regularFont)
		bold = addFont(boldFont)
	}
	imgui.PushFont(regular, 18)
	defer imgui.PopFont()

	vp := imgui.MainViewport()
	imgui.SetNextWindowPos(vp.WorkPos())
	imgui.SetNextWindowSize(vp.WorkSize())
	imgui.BeginV("main", nil, imgui.WindowFlagsNoTitleBar|imgui.WindowFlagsNoResize|imgui.WindowFlagsNoMove|
		imgui.WindowFlagsNoCollapse|imgui.WindowFlagsNoSavedSettings|imgui.WindowFlagsNoBringToFrontOnFocus)

	width = min(imgui.ContentRegionAvail().X, 600*scale)
	if margin := (imgui.ContentRegionAvail().X - width) / 2; margin > 0 {
		imgui.IndentV(margin)
	}
	imgui.PushTextWrapPosV(imgui.CursorPosX() + width)

	imgui.PushFont(bold, 32)
	imgui.TextUnformatted("Let's make your game")
	imgui.PopFont()
	colored(muted, "Yumetaro from Gimmick! takes Mario's place in Super Mario Bros. 3. Add the two games below. Everything happens on this computer.")
	imgui.Spacing()

	if problem != "" {
		panel("problem", warnBg, warnBg, func() { colored(warn, problem) })
	}

	panel("drop", card, line, func() {
		centered(muted, "Drop both game files on this window")
		if dialogs {
			centered(muted, "or")
			label := "Choose files"
			w := imgui.CalcTextSize(label).X + imgui.CurrentStyle().FramePadding().X*2
			imgui.SetCursorPosX(imgui.CursorPosX() + (imgui.ContentRegionAvail().X-w)/2)
			imgui.BeginDisabledV(busy)
			if imgui.Button(label) {
				busy = true
				go choose()
			}
			imgui.EndDisabled()
		}
	})

	gameCard("smb3", "Super Mario Bros. 3", smb3, "Waiting for the original US game")
	gameCard("gimmick", "Gimmick!", gimmick, "Waiting for the Japanese game")
	imgui.Spacing()

	if savedTo == "" {
		ready := smb3.data != nil && gimmick.data != nil
		label := "Make the game###make"
		if busy && ready {
			label = "Making it…###make"
		}
		bg := green
		if !ready || busy {
			bg = rgb(0xc9c1b6)
		}
		imgui.PushStyleColorVec4(imgui.ColButton, bg)
		imgui.PushStyleColorVec4(imgui.ColButtonHovered, greenDark)
		imgui.PushStyleColorVec4(imgui.ColButtonActive, greenDark)
		imgui.PushStyleColorVec4(imgui.ColText, white)
		imgui.PushFont(imgui.CurrentFont(), 20)
		imgui.BeginDisabledV(!ready || busy)
		if imgui.ButtonV(label, imgui.Vec2{X: width, Y: imgui.FrameHeight() * 1.4}) {
			busy = true
			go makeGame(smb3.data, gimmick.data, filepath.Join(filepath.Dir(smb3.path), outName))
		}
		imgui.EndDisabled()
		imgui.PopFont()
		imgui.PopStyleColorV(4)
	} else {
		panel("done", soft, softLine, func() {
			imgui.PushFont(bold, 22)
			imgui.TextUnformatted("Your game is ready")
			imgui.PopFont()
			imgui.TextUnformatted("It was saved as " + savedTo + ". Open it with an NES emulator.")
			if imgui.Button("Show in folder") {
				reveal(savedTo)
			}
		})
	}

	imgui.Spacing()
	imgui.Spacing()
	colored(muted, "Super Mario Bros. 3 is Nintendo's game. Gimmick! is Sunsoft's game.")
	colored(muted, "Version "+version)

	imgui.PopTextWrapPos()
	imgui.End()
}

func panel(id string, bg, border imgui.Vec4, body func()) {
	imgui.PushStyleColorVec4(imgui.ColChildBg, bg)
	imgui.PushStyleColorVec4(imgui.ColBorder, border)
	imgui.PushStyleVarVec2(imgui.StyleVarWindowPadding, imgui.Vec2{X: 18 * scale, Y: 14 * scale})
	imgui.PushStyleVarVec2(imgui.StyleVarItemSpacing, imgui.Vec2{X: 10 * scale, Y: 6 * scale})
	imgui.BeginChildStrV(id, imgui.Vec2{X: width}, imgui.ChildFlagsBorders|imgui.ChildFlagsAutoResizeY|imgui.ChildFlagsAlwaysUseWindowPadding, 0)
	imgui.PushTextWrapPosV(0)
	body()
	imgui.PopTextWrapPos()
	imgui.EndChild()
	imgui.PopStyleVarV(2)
	imgui.PopStyleColorV(2)
}

func gameCard(id, title string, gm game, waiting string) {
	bg, border, state, col := card, line, waiting, muted
	if gm.data != nil {
		bg, border, state, col = soft, softLine, filepath.Base(gm.path), greenDark
	}
	panel(id, bg, border, func() {
		imgui.PushFont(bold, 0)
		imgui.TextUnformatted(title)
		imgui.PopFont()
		colored(col, state)
	})
}

func addFont(data []byte) *imgui.Font {
	cfg := imgui.NewFontConfig()
	cfg.SetFontDataOwnedByAtlas(false)
	return imgui.CurrentIO().Fonts().AddFontFromMemoryTTFV(uintptr(unsafe.Pointer(&data[0])), int32(len(data)), 0, cfg, nil)
}

func colored(col imgui.Vec4, text string) {
	imgui.PushStyleColorVec4(imgui.ColText, col)
	imgui.TextUnformatted(text)
	imgui.PopStyleColor()
}

func centered(col imgui.Vec4, text string) {
	w := imgui.CalcTextSize(text).X
	imgui.SetCursorPosX(imgui.CursorPosX() + (imgui.ContentRegionAvail().X-w)/2)
	colored(col, text)
}
