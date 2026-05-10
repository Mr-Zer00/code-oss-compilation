# code-oss-compilation

A set of shell scripts to automatically download, compile, install, and update Code-OSS on Linux.

This project provides a fully automated way to build and maintain a telemetry-free version of Code-OSS from source.

> Code-OSS is the open-source version of Visual Studio Code maintained by Microsoft.

---

## ⚠️ Disclaimer

This project is not affiliated with Microsoft or the Visual Studio Code team.

Code-OSS is distributed under the MIT License.


---

## 📦 What This Project Does

This project provides two main scripts:

- `install-codeoss.sh` → Compiles Code-OSS, and installs it automatically
- `update-codeoss.sh` → Updates the existing installation and rebuilds when needed

After the initial setup, everything is fully automated.

---

## 🧰 Requirements

Before running the scripts, install the following dependencies:

### System packages

- build-essential
- g++
- libx11-dev
- libxkbfile-dev
- libsecret-1-dev
- libkrb5-dev
- python3
- fakeroot
- rpm
- git
- curl
- wget

### Node.js environment

- nvm
- Node.js 22
- npm

---

## 🚀 Installation

1. Clone this repository:

```bash
git clone https://github.com/your-username/code-oss-compilation.git
cd code-oss-compilation
