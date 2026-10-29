# Offline bundle guide (air-gapped classroom)

Trainer guide. Two targets: **Windows 11 + WSL2 Ubuntu (amd64)** and **macOS Apple Silicon (arm64)**.
Status: the macOS arm64 build is produced by `scripts/build-offline-bundle.sh arm64` (see section 2). The Windows/WSL steps in section 1 are **not yet tested end to end**; they use the same script, which builds natively on an amd64 machine.

Bundle layout (what the script produces, per architecture):

| Folder | Content |
|---|---|
| `bin/<os>-<arch>/` | kind, kubectl, helm, trivy, syft, uv |
| `python/` | Python 3.12 standalone builds for `uv python install` |
| `wheelhouse/` | every pinned Python wheel (`requirements.txt`: mlflow 3.17.2, evidently 0.7.23, fastapi, dvc 3.67.1, ...) |
| `trivy-cache/` | Trivy vulnerability DB (offline scanning; dated in `DB_DATE`, refresh before each course) |
| `charts/` | Traefik Helm chart 41.5.0 |
| `images/all-images.tar.gz` | all container images (docker load) |
| `images/kind-preload.tar.gz` | images preloaded into the kind node |
| `vm/` | Ubuntu cloud image (Multipass option, session 10) |
| `compose/`, `k8s/`, `scripts/`, `versions.env`, `requirements.txt`, `SHA256SUMS` | lab kit and checksums |

Container images in the bundle: kind node, SeaweedFS, registry, Gitea, act_runner, python 3.12 slim, uv, nginx, Traefik, Prometheus, Grafana, plus the course images `mlops/mlflow-server:3.17.2`, `mlops/ci-job:1.0` (Trivy DB baked in), `mlops/practice-vm:24.04`.

---

## 1. Windows + WSL2 (amd64)

Students run **everything inside WSL2 Ubuntu**, not PowerShell.

### 1.1 Things to download on the internet-connected Windows PC (outside the bundle script)

Put these in the drive folder `windows-installers/`. Check each URL once, vendors move files.

| Item | Where | Used for |
|---|---|---|
| Docker Desktop for Windows (amd64) | `https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe` | Docker engine with WSL2 integration |
| WSL2 kernel/installer MSI | `https://github.com/microsoft/WSL/releases` (latest `wsl.*.x64.msi`) | `wsl --install` needs internet otherwise |
| Ubuntu 24.04 WSL image (`.wsl` / rootfs, amd64) | `https://releases.ubuntu.com/noble/` (file named `ubuntu-24.04.*-wsl-amd64.wsl`) | install Ubuntu without the Store: double-click the `.wsl` file or `wsl --import` |
| VS Code (optional) | `https://code.visualstudio.com/Download` | editor |
| Git for Windows (optional) | `https://git-scm.com/download/win` | only if a student wants Git outside WSL |

Windows needs virtualization enabled in BIOS, and the "Virtual Machine Platform" and "Windows Subsystem for Linux" features (enable with `dism.exe` or `wsl --install --no-distribution` once while online, or ship the MSI above).

### 1.2 Build the amd64 bundle (one machine with internet)

Use a Windows PC (or a Linux amd64 machine) with WSL2 Ubuntu 24.04, Docker Desktop (WSL integration on), then inside WSL:

```bash
sudo apt-get update && sudo apt-get install -y curl git perl xz-utils
curl -LsSf https://astral.sh/uv/install.sh | sh        # uv
curl -fsSL https://get.helm.sh/helm-v4.2.4-linux-amd64.tar.gz | sudo tar -xz -C /usr/local/bin --strip-components=1 linux-amd64/helm
docker buildx version && helm version --short && uv --version
```

The student GitHub repo does not contain the build inputs (`ci-image/`, `compose/mlflow/`). Copy the trainer's `lab-kit/` folder to the WSL machine (USB), then run from its root:

```bash
cd ~/lab-kit
BUNDLE_OUT=/mnt/d/MLOps-Fund-Offline-Bundle/bundle-amd64 bash scripts/build-offline-bundle.sh amd64
```

Notes:
- Output path `/mnt/d/...` is the Windows drive seen from WSL. Better build on the WSL ext4 disk (`~/bundle-amd64`) and copy to the drive afterwards: exFAT has no symlinks and no exec bit.
- Needs about 25 to 35 GB free during the build. The run takes a long time (images, wheels for linux and darwin, Python builds). Run it in `tmux` or with `nohup`.
- When it ends it prints `SHA256SUMS` and the folder size. Check: `cd bundle-amd64 && shasum -a 256 -c SHA256SUMS --quiet`.
- The script downloads binaries for both `linux-amd64` and `darwin-amd64` (Intel Macs). Windows students only use the linux set.

### 1.3 Install on an air-gapped student PC

1. Install Docker Desktop (installer from `windows-installers/`), enable WSL integration for Ubuntu. Restart if asked.
2. Install the Ubuntu 24.04 WSL image (double-click the `.wsl` file). Create the Linux user.
3. Copy the bundle from the drive into WSL's Linux disk (do not run from `/mnt/...`, it is slow):

```bash
cp -r /mnt/e/MLOps-Fund-Offline-Bundle/bundle-amd64 ~/bundle-amd64
cd ~/bundle-amd64
```

4. Install:

```bash
bash scripts/install-from-bundle.sh
```

It checks `SHA256SUMS`, installs the CLIs into `~/.local/bin`, points `uv` at the local Python builds and wheelhouse (`no-index = true`), loads Trivy DB and images into Docker, and copies the lab kit to `~/mlops-lab`. Then:

```bash
cd ~/mlops-lab && ./scripts/preflight.sh
```

5. Classroom services come from `~/mlops-lab/compose` (Gitea, SeaweedFS, MLflow) as in session 3 and later; the student project lives in `~/work/churn-mlops` inside WSL.

### 1.4 Known gaps (Windows/WSL)

- Untested end to end on a real air-gapped Windows machine.
- `docker build` in sessions 9, 13 and 14 downloads wheels from PyPI. In an air-gapped room the Dockerfile must install from the bundle wheelhouse (pip `--no-index --find-links`) or a classroom PyPI mirror. This is still open.
- Trivy DB ages: rebuild the bundle (or just `trivy-cache/`) shortly before the course.
- Multipass is only the optional "real VM" for session 10; the course default is the container VM `mlops/practice-vm:24.04`.

---

## 2. macOS Apple Silicon (arm64) from the local drive

### 2.1 Build (internet-connected Mac, already running)

```bash
cd ~/projects/MLOps-Fund/lab-kit
BUNDLE_OUT=/Volumes/Saeed/IT/MLOps-Fund-Offline-Bundle/bundle-arm64 ./scripts/build-offline-bundle.sh arm64
```

Needs docker with buildx, helm, uv, curl. It builds the three `mlops/*` images natively for arm64, so it does not touch your tags unless an image with the same name already exists locally (the `mlops/*` tags are rebuilt). Progress is written to the terminal (this session: the scratchpad file `bundle-arm64.log`). When done, verify:

```bash
cd /Volumes/Saeed/IT/MLOps-Fund-Offline-Bundle/bundle-arm64
shasum -a 256 -c SHA256SUMS --quiet && echo OK
du -sh *
```

### 2.2 Download outside the script

| Item | Where |
|---|---|
| Docker Desktop for Mac (Apple Silicon) | `https://desktop.docker.com/mac/main/arm64/Docker.dmg` |
| VS Code (optional) | `https://code.visualstudio.com/Download` |

Put the `.dmg` files in `/Volumes/Saeed/IT/MLOps-Fund-Offline-Bundle/macos-installers/`. Xcode command line tools are needed for `git`; `xcode-select --install` needs internet, so install them beforehand.

### 2.3 Install on an air-gapped Mac from the drive

1. Install Docker Desktop from the `.dmg`, start it, give it at least 6 GB memory (Settings, Resources; the full chain used about 3.6 GiB at peak).
2. Copy the bundle to the local disk (faster than running from the USB drive, and the exFAT drive loses the exec bit):

```bash
cp -R /Volumes/Saeed/IT/MLOps-Fund-Offline-Bundle/bundle-arm64 ~/bundle-arm64
cd ~/bundle-arm64
```

3. Install:

```bash
bash scripts/install-from-bundle.sh
```

4. Open a new terminal (so `~/.local/bin` is on `PATH`) and check:

```bash
cd ~/mlops-lab && ./scripts/preflight.sh
```

5. Start the classroom stack as in session 3 and continue with the sessions.

### 2.4 Known gaps (macOS)

- The `docker build` PyPI gap above applies here too.
- `install-from-bundle.sh` writes `~/.config/uv/uv.toml` with `no-index = true`. After the course, delete that file to use PyPI again.
- Old bundle folder `lab-kit/bundle-arm64` (partial, from earlier today) is left untouched; use the drive one.
