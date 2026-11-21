package platform

import (
	"os"
	"path/filepath"
	"strings"
)

// LeaveAppImage undoes, for the programs envsetup starts, what the AppImage
// of the app sets up for itself.
//
// The AppImage runs from a FUSE mount (/tmp/.mount_envsetXXXX, $APPDIR) and
// its AppRun points LD_LIBRARY_PATH, PATH, XDG_DATA_DIRS, GIO/GTK/GDK
// variables... into it. A child inherits that: the system curl then loads the
// AppImage's libnghttp2 and dies with "undefined symbol", and so do git over
// https, fish, yay and `pacman -Qi` (which made installed packages look
// missing). The working directory may also be inside the mount, which other
// users (root, under sudo) cannot read: pacman hooks then fail with "could not
// get the current working directory".
//
// So every entry under $APPDIR is taken out of the environment (a variable
// left empty is removed) and the working directory moves out of the mount.
// $APPDIR, $APPIMAGE, $ARGV0 and $OWD themselves stay: they only describe the
// AppImage. Outside an AppImage it does nothing.
func LeaveAppImage() {
	dir := os.Getenv("APPDIR")
	if dir == "" {
		return
	}
	for _, kv := range os.Environ() {
		k, v, ok := strings.Cut(kv, "=")
		if !ok || keepAppImageVar[k] {
			continue
		}
		if nv, changed := withoutDir(v, dir); changed {
			if nv == "" {
				os.Unsetenv(k)
			} else {
				os.Setenv(k, nv)
			}
		}
	}
	if wd, err := os.Getwd(); err == nil && !under(wd, dir) {
		return
	}
	for _, d := range []string{os.Getenv("OWD"), os.Getenv("HOME"), "/"} {
		if d != "" && !under(d, dir) && os.Chdir(d) == nil {
			return
		}
	}
}

var keepAppImageVar = map[string]bool{"APPDIR": true, "APPIMAGE": true, "ARGV0": true, "OWD": true}

// withoutDir drops the entries of a colon-separated list that are under dir.
// A value that is not under dir at all is returned unchanged.
func withoutDir(value, dir string) (string, bool) {
	if !strings.Contains(value, dir) {
		return value, false
	}
	var keep []string
	for _, p := range strings.Split(value, ":") {
		if p == "" || under(p, dir) {
			continue
		}
		keep = append(keep, p)
	}
	return strings.Join(keep, ":"), true
}

func under(path, dir string) bool {
	path, dir = filepath.Clean(path), filepath.Clean(dir)
	return path == dir || strings.HasPrefix(path, dir+string(filepath.Separator))
}
