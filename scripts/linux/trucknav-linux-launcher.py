#!/usr/bin/env python3
"""Small Fedora/Linux launcher GUI for TruckNav-Sim."""
from __future__ import annotations

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
        "TruckNav Linux Launcher",
        "Could not detect the TruckNav-Sim repository root. Set TRUCKNAV_REPO_ROOT and try again.",
    )
    sys.exit(1)


REPO_ROOT = find_repo_root()
SCRIPT_DIR = REPO_ROOT / "scripts" / "linux"


class Launcher(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("TruckNav Linux Launcher")
        self.geometry("720x520")
        self.minsize(640, 440)
        self.processes: list[subprocess.Popen[str]] = []
        self.stop_trucknav_on_close = tk.BooleanVar(value=False)

        heading = tk.Label(self, text="TruckNav Linux Launcher", font=("Sans", 18, "bold"))
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

        close_options = tk.Frame(self)
        close_options.pack(fill="x", padx=24, pady=(4, 0))
        stop_on_close = tk.Checkbutton(
            close_options,
            text="Stop TruckNav when closing launcher",
            variable=self.stop_trucknav_on_close,
            anchor="w",
        )
        stop_on_close.pack(anchor="w")

        close_note = tk.Label(
            close_options,
            text="Closing this launcher does not stop TruckNav unless enabled.",
            anchor="w",
            justify="left",
        )
        close_note.pack(fill="x", pady=(2, 0))

        self.output = scrolledtext.ScrolledText(self, height=14, state="disabled")
        self.output.pack(fill="both", expand=True, padx=18, pady=(8, 14))

        self.protocol("WM_DELETE_WINDOW", self.on_close)
        self.append_output("Use Check dependencies/status first if this is a new Fedora setup.\n")

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
