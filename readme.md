# network_analysis_hw1
Homework.
## requirement
```
zig >= 0.14.0-dev.1658+efc98fcbe
```
## execute step

### build
#### debug build
```bash
zig build
```
#### release build
```bash
zig build -Doptimize=ReleaseSafe
```
### run
#### windows
```
cd zig-out/bin
network_sim.exe
```
#### linux
```
cd zig-out/bin
network_sim
```