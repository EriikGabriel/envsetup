package platform

import (
	"os"
	"runtime"
	"testing"
)

func TestLeaveAppImage(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("AppImages only exist on Linux")
	}
	dir := t.TempDir() + "/.mount_envsetX"
	if err := os.MkdirAll(dir+"/usr", 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("APPDIR", dir)
	t.Setenv("APPIMAGE", "/home/u/envsetup.AppImage")
	t.Setenv("LD_LIBRARY_PATH", dir+"/usr/lib:"+dir+"/usr/lib/x86_64-linux-gnu")
	t.Setenv("PATH", dir+"/usr/bin:/usr/local/bin:/usr/bin")
	t.Setenv("XDG_DATA_DIRS", dir+"/usr/share:/usr/share")
	t.Setenv("GIO_MODULE_DIR", dir+"/usr/lib/gio/modules")
	t.Setenv("LANG", "pt_BR.UTF-8")
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("OWD", "")
	wd, _ := os.Getwd()
	t.Cleanup(func() { os.Chdir(wd) })
	if err := os.Chdir(dir + "/usr"); err != nil {
		t.Fatal(err)
	}

	LeaveAppImage()

	if v, ok := os.LookupEnv("LD_LIBRARY_PATH"); ok {
		t.Errorf("LD_LIBRARY_PATH must go, got %q", v)
	}
	if v, ok := os.LookupEnv("GIO_MODULE_DIR"); ok {
		t.Errorf("GIO_MODULE_DIR must go, got %q", v)
	}
	if got := os.Getenv("PATH"); got != "/usr/local/bin:/usr/bin" {
		t.Errorf("PATH = %q", got)
	}
	if got := os.Getenv("XDG_DATA_DIRS"); got != "/usr/share" {
		t.Errorf("XDG_DATA_DIRS = %q", got)
	}
	if os.Getenv("APPDIR") != dir || os.Getenv("APPIMAGE") == "" || os.Getenv("LANG") != "pt_BR.UTF-8" {
		t.Error("APPDIR, APPIMAGE and unrelated variables must stay")
	}
	if got, _ := os.Getwd(); got != home {
		t.Errorf("working directory = %q, want %q", got, home)
	}
}

func TestLeaveAppImageOutsideAnAppImage(t *testing.T) {
	t.Setenv("APPDIR", "")
	t.Setenv("LD_LIBRARY_PATH", "/opt/x/lib")
	LeaveAppImage()
	if os.Getenv("LD_LIBRARY_PATH") != "/opt/x/lib" {
		t.Error("nothing changes outside an AppImage")
	}
}
