## Development Environment 


---

### Requirements

- `pyenv` (with `pyenv-virtualenv`)
- VSCodium IDE
- `bash`

--- 

### Quick Start

1. Create `pyenv` virtual environment with:
   ```bash
   ./scripts/steup-pyenv.bash
   ```

2. VSCodium:
   1. Download `./scripts/vsix-downloader.py`
   2. Optionally create VSCodium profile
   3. Install recommended extensions, and the downloaded `platformio` extension from `.vsix` file in `.vscode_exts` directory:
      ```
      codium --install-extension ".vscode_exts/platformio.platformio-ide-*.vsix"
      ```
   4. Patch the installed extension with `./scripts/patch.bash` _(by default platformio requires `ms-vscode.cpptools` which refuses to run on VSCode forks like VSCodium)_

   > 📌 _**Note on VSCodium False Positive Warnings**_
   >
   > VSCodium during the installation procedure will spew warnings about missing and conflicting dependencies, but that's expected behaviour

3. To add or remove compilation flags please look into `./pio-clangd` submodule directory, refer to its [README.md](./pio-clangd/README.md)