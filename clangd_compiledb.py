import os
Import("env")

# Make compile_commands.json usable for clangd (toolchain + sysroot includes)
env.Replace(COMPILATIONDB_INCLUDE_TOOLCHAIN=True)

# Optional: if you prefer putting it into the env build dir instead:
# env.Replace(COMPILATIONDB_PATH=os.path.join("$BUILD_DIR", "compile_commands.json"))
env.Replace(COMPILATIONDB_PATH="compile_commands.json")