#!/usr/bin/env python3
"""Small Fedora/Linux launcher GUI for TruckNav-Sim."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import tkinter as tk
import webbrowser
from pathlib import Path
from tkinter import messagebox, scrolledtext

ATS_APP_ID = os.environ.get("TRUCKNAV_ATS_APP_ID", "270880")
TRUCKNAV_URL = os.environ.get("TRUCKNAV_URL", "http://127.0.0.1:3000/")
WINDOW_CLASS = "TruckNavLinuxLauncher"
WINDOW_TITLE = "TruckNav Linux Launcher"
CONFIG_PATH = (
    Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    / "trucknav-linux-launcher"
    / "config.json"
)

THEMES = {
    "light": {
        "window_bg": "#f4f4f4",
        "panel_bg": "#f4f4f4",
        "text_fg": "#1f2328",
        "muted_fg": "#4f5660",
        "button_bg": "#ffffff",
        "button_fg": "#1f2328",
        "button_active_bg": "#e9eef6",
        "button_active_fg": "#111827",
        "field_bg": "#ffffff",
        "field_fg": "#1f2328",
        "insert_bg": "#1f2328",
        "select_bg": "#b7d7ff",
        "select_fg": "#000000",
    },
    "dark": {
        "window_bg": "#171a21",
        "panel_bg": "#171a21",
        "text_fg": "#f2f5f8",
        "muted_fg": "#b7c0cc",
        "button_bg": "#2a2f3a",
        "button_fg": "#f2f5f8",
        "button_active_bg": "#3a4352",
        "button_active_fg": "#ffffff",
        "field_bg": "#0f131a",
        "field_fg": "#e6edf3",
        "insert_bg": "#e6edf3",
        "select_bg": "#355c9a",
        "select_fg": "#ffffff",
    },
}


def find_repo_root() -> Path:
    env_root = os.environ.get("TRUCKNAV_REPO_ROOT")
    if env_root:
        candidate = Path(env_root).expanduser().resolve()
        if (candidate / "package.json").is_file():
            return candidate

    current = Path(__file__).resolve()
    for parent in [current.parent, *current.parents]:
        if (parent / "package.json").is_file() and (parent / "nuxt.config.ts").is_file():
            return parent

    try:
        git_root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        candidate = Path(git_root).resolve()
        if (candidate / "package.json").is_file():
            return candidate
    except (OSError, subprocess.CalledProcessError):
        pass

    messagebox.showerror(
        WINDOW_TITLE,
        "Could not detect the TruckNav-Sim repository root. Set TRUCKNAV_REPO_ROOT and try again.",
    )
    sys.exit(1)


def load_config() -> dict[str, object]:
    try:
        with CONFIG_PATH.open("r", encoding="utf-8") as config_file:
            loaded = json.load(config_file)
    except (OSError, json.JSONDecodeError):
        return {}

    if isinstance(loaded, dict):
        return loaded
    return {}


def save_config(config: dict[str, object]) -> None:
    try:
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with CONFIG_PATH.open("w", encoding="utf-8") as config_file:
            json.dump(config, config_file, indent=2)
            config_file.write("\n")
    except OSError as exc:
        print(f"Could not save launcher config to {CONFIG_PATH}: {exc}", file=sys.stderr)


REPO_ROOT = find_repo_root()
SCRIPT_DIR = REPO_ROOT / "scripts" / "linux"
ICON_PATH = REPO_ROOT / "assets" / "icon-only.png"


class Launcher(tk.Tk):
    def __init__(self) -> None:
        # KDE and other desktop shells can match this class with the
        # desktop file StartupWMClass so the running taskbar entry uses the
        # TruckNav icon instead of Tk's generic X icon.
        super().__init__(className=WINDOW_CLASS)
        self.title(WINDOW_TITLE)
        self.set_window_icon()
        self.geometry("720x560")
        self.minsize(640, 480)
        self.processes: list[subprocess.Popen[str]] = []
        self.config_data = load_config()
        self.dark_mode = tk.BooleanVar(value=self.config_data.get("dark_mode") is True)
        self.stop_trucknav_on_close = tk.BooleanVar(value=False)

        heading = tk.Label(self, text=WINDOW_TITLE, font=("Sans", 18, "bold"))
        heading.pack(pady=(14, 4))

        subtitle = tk.Label(
            self,
            text=f"Repo: {REPO_ROOT}\nATS Steam app id: {ATS_APP_ID}",
            justify="center",
        )
        subtitle.pack(pady=(0, 10))

        button_frame = tk.Frame(self)
        button_frame.pack(fill="x", padx=18)

        buttons = [
            ("Install/repair Fedora setup", self.install_fedora),
            ("Launch TruckNav only", lambda: self.run_script("launch-trucknav.sh", wait=False)),
            ("Launch ATS + TruckNav together", lambda: self.run_script("launch-ats-trucknav.sh", wait=False)),
            ("Stop TruckNav", lambda: self.run_script("stop-trucknav.sh", wait=True)),
            ("Open TruckNav in browser", self.open_browser),
            ("Check dependencies/status", lambda: self.run_script("check-status.sh", wait=True)),
        ]

        for index, (label, command) in enumerate(buttons):
            button = tk.Button(button_frame, text=label, command=command, height=2)
            button.grid(row=index // 2, column=index % 2, sticky="ew", padx=6, pady=6)
        button_frame.columnconfigure(0, weight=1)
        button_frame.columnconfigure(1, weight=1)

        options_frame = tk.Frame(self)
        options_frame.pack(fill="x", padx=24, pady=(4, 0))
        stop_on_close = tk.Checkbutton(
            options_frame,
            text="Stop TruckNav when closing launcher",
            variable=self.stop_trucknav_on_close,
            anchor="w",
        )
        stop_on_close.pack(anchor="w")

        dark_mode_toggle = tk.Checkbutton(
            options_frame,
            text="Dark mode",
            variable=self.dark_mode,
            command=self.toggle_dark_mode,
            anchor="w",
        )
        dark_mode_toggle.pack(anchor="w", pady=(2, 0))

        close_note = tk.Label(
            options_frame,
            text="Closing this launcher does not stop TruckNav unless enabled.",
            anchor="w",
            justify="left",
        )
        close_note.pack(fill="x", pady=(2, 0))

        self.output = scrolledtext.ScrolledText(self, height=14, state="disabled")
        self.output.pack(fill="both", expand=True, padx=18, pady=(8, 14))

        self.apply_theme()
        self.protocol("WM_DELETE_WINDOW", self.on_close)
        self.append_output("Use Check dependencies/status first if this is a new Fedora setup.\n")

    def set_window_icon(self) -> None:
        try:
            self.icon_image = tk.PhotoImage(file=ICON_PATH)
            self.iconphoto(True, self.icon_image)
        except (OSError, tk.TclError) as exc:
            print(f"Could not load launcher window icon from {ICON_PATH}: {exc}", file=sys.stderr)

    def current_theme(self) -> dict[str, str]:
        return THEMES["dark" if self.dark_mode.get() else "light"]

    def apply_theme(self) -> None:
        theme = self.current_theme()
        self.configure(bg=theme["window_bg"])
        for child in self.winfo_children():
            self.apply_theme_to_widget(child, theme)

    def apply_theme_to_widget(self, widget: tk.Widget, theme: dict[str, str]) -> None:
        if isinstance(widget, tk.Button):
            widget.configure(
                bg=theme["button_bg"],
                fg=theme["button_fg"],
                activebackground=theme["button_active_bg"],
                activeforeground=theme["button_active_fg"],
                highlightbackground=theme["panel_bg"],
            )
        elif isinstance(widget, tk.Checkbutton):
            widget.configure(
                bg=theme["panel_bg"],
                fg=theme["text_fg"],
                activebackground=theme["panel_bg"],
                activeforeground=theme["text_fg"],
                selectcolor=theme["field_bg"],
                highlightbackground=theme["panel_bg"],
            )
        elif isinstance(widget, scrolledtext.ScrolledText):
            widget.configure(
                bg=theme["field_bg"],
                fg=theme["field_fg"],
                insertbackground=theme["insert_bg"],
                selectbackground=theme["select_bg"],
                selectforeground=theme["select_fg"],
                highlightbackground=theme["panel_bg"],
            )
        elif isinstance(widget, tk.Label):
            widget.configure(bg=theme["panel_bg"], fg=theme["text_fg"])
        elif isinstance(widget, tk.Frame):
            widget.configure(bg=theme["panel_bg"], highlightbackground=theme["panel_bg"])

        for child in widget.winfo_children():
            self.apply_theme_to_widget(child, theme)

    def toggle_dark_mode(self) -> None:
        self.apply_theme()
        self.config_data["dark_mode"] = self.dark_mode.get()
        save_config(self.config_data)

    def env(self) -> dict[str, str]:
        env = os.environ.copy()
        env["TRUCKNAV_REPO_ROOT"] = str(REPO_ROOT)
        env["TRUCKNAV_ATS_APP_ID"] = ATS_APP_ID
        env["TRUCKNAV_URL"] = TRUCKNAV_URL
        return env

    def append_output(self, text: str) -> None:
        self.output.configure(state="normal")
        self.output.insert("end", text)
        self.output.see("end")
        self.output.configure(state="disabled")

    def run_script(self, script_name: str, wait: bool) -> None:
        script = SCRIPT_DIR / script_name
        if not script.is_file():
            messagebox.showerror("Missing script", f"Could not find {script}")
            return

        self.append_output(f"\n$ {script}\n")
        try:
            if wait:
                result = subprocess.run(
                    [str(script)],
                    cwd=REPO_ROOT,
                    env=self.env(),
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    check=False,
                )
                self.append_output(result.stdout or "")
                if result.returncode != 0:
                    messagebox.showerror(
                        "TruckNav command failed",
                        f"{script_name} exited with status {result.returncode}. See output for details.",
                    )
            else:
                process = subprocess.Popen(
                    [str(script)],
                    cwd=REPO_ROOT,
                    env=self.env(),
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                )
                self.track_process(process)
        except FileNotFoundError as exc:
            messagebox.showerror("Command not found", str(exc))
        except OSError as exc:
            messagebox.showerror("Could not run command", str(exc))

    def install_fedora(self) -> None:
        installer = REPO_ROOT / "scripts" / "install-fedora.sh"
        if not installer.is_file():
            messagebox.showerror("Missing installer", f"Could not find {installer}")
            return
        self.append_output(f"\n$ {installer}\n")
        process = subprocess.Popen(
            [str(installer)],
            cwd=REPO_ROOT,
            env=self.env(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        self.track_process(process)

    def track_process(self, process: subprocess.Popen[str]) -> None:
        self.processes.append(process)
        thread = threading.Thread(target=self.drain_process, args=(process,), daemon=True)
        thread.start()

    def drain_process(self, process: subprocess.Popen[str]) -> None:
        if process.stdout is not None:
            for line in process.stdout:
                self.after(0, self.append_output, line)
        return_code = process.wait()
        self.after(0, self.process_finished, process, return_code)

    def process_finished(self, process: subprocess.Popen[str], return_code: int) -> None:
        self.append_output(f"Command exited with status {return_code}.\n")
        if process in self.processes:
            self.processes.remove(process)

    def open_browser(self) -> None:
        self.append_output(f"Opening {TRUCKNAV_URL}\n")
        webbrowser.open(TRUCKNAV_URL)

    def stop_trucknav_before_close(self) -> None:
        stop_script = SCRIPT_DIR / "stop-trucknav.sh"
        if not stop_script.is_file():
            messagebox.showerror("Missing script", f"Could not find {stop_script}")
            return

        self.append_output("\nClosing launcher: stopping TruckNav web app and telemetry only. Steam/ATS will not be stopped.\n")
        result = subprocess.run(
            [str(stop_script)],
            cwd=REPO_ROOT,
            env=self.env(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        self.append_output(result.stdout or "")
        if result.returncode != 0:
            messagebox.showerror(
                "TruckNav stop failed",
                f"stop-trucknav.sh exited with status {result.returncode}. See output for details.",
            )

    def on_close(self) -> None:
        if self.stop_trucknav_on_close.get():
            self.stop_trucknav_before_close()
        else:
            message = "Closing launcher: leaving TruckNav running. Use Stop TruckNav to stop the web app and telemetry.\n"
            self.append_output(message)
            print(message, end="")

        for process in list(self.processes):
            if process.poll() is None:
                process.terminate()
        self.destroy()


if __name__ == "__main__":
    Launcher().mainloop()
