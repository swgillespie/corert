The following pre-requisites need to be installed for building the repo:

# Common Pre-requisites

1. CMake is used for the build system and needs to be installed and present on the path. You can download it from [here](http://www.cmake.org/download/).

# Windows (Windows 7+)

Install [Visual Studio 2015](https://www.visualstudio.com/en-us/products/visual-studio-community-vs.aspx), including Visual C++ support.

# Ubuntu (14.04)

Install basic dependency packages:

```
sudo apt-get install llvm-3.5 clang-3.5 lldb-3.6 lldb-3.6-dev libunwind8 libunwind8-dev liblttng-ust liblttng-ust-dev uuid uuid-dev
```


Next, install [Mono](http://www.mono-project.com/docs/getting-started/install/linux/#debian-ubuntu-and-derivatives). Specific steps are copied below:

```
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF
echo "deb http://download.mono-project.com/repo/debian wheezy main" | sudo tee /etc/apt/sources.list.d/mono-xamarin.list
sudo apt-get update
```

Next, install the **mono-complete** and **referenceassemblies-pcl** packages using the commands below:

```
sudo apt-get install mono-complete
sudo apt-get install referenceassemblies-pcl
```

# Mac OSX (10.10+)

Install [Command Line Tools for XCode 6.3.1](https://developer.apple.com/xcode/download/) or higher. 

Next, install [Mono](http://www.mono-project.com/docs/getting-started/install/mac/)

Download CMake from https://cmake.org/download/ and launch `/Applications/CMake.app/Contents/MacOS/CMake` GUI. Goto "OSX App Menu -> Tools -> Install For Command Line Use" and follow the steps.
