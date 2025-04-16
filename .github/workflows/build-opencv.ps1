# PowerShell script to build OpenCV on Windows

# Exit on error
$ErrorActionPreference = "Stop"

# Variables
$OpenCVVersion = "4.5.5"
$OpenCVVersionNoDot = $OpenCVVersion -replace '\.', ''
$OpenCVContribVersion = "4.x"
$InstallDir = "C:\opencv_install"
$BuildDir = "$env:USERPROFILE\opencv_build"
$NumJobs = [Environment]::ProcessorCount

$env:JAVA_HOME = $env:JAVA_HOME_8_X64
$env:VCPKG_ROOT = $env:VCPKG_INSTALLATION_ROOT
$env:VCPKG_DISABLE_METRICS = "1"
$env:VCPKG_DEFAULT_TRIPLET = "x64-windows-static"
$env:VCPKG_BUILD_TYPE = "release"

# Create build directory
if (-Not (Test-Path -Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir | Out-Null
}

# Function to install BellSoft JDK 8
function Install-BellSoftJDK8 {
    $Url = "https://download.bell-sw.com/java/8u432+7/bellsoft-jdk8u432+7-windows-amd64.zip"
    $Archive = "$env:TEMP\bellsoft-jdk8u432+7-windows-amd64.zip"
    $InstallDir = "C:\Program Files\BellSoft\JDK8"

    if ((Get-Command java -ErrorAction SilentlyContinue) -and (& java -version 2>&1 | Select-String "1.8")) {
        Write-Host "JDK 8 is already installed."
        return
    }

    Write-Host "Installing BellSoft JDK 8..."
    Invoke-WebRequest -Uri $Url -OutFile $Archive
    Expand-Archive -Path $Archive -DestinationPath $InstallDir -Force

    # Set environment variables
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $InstallDir, [EnvironmentVariableTarget]::Machine)
    [Environment]::SetEnvironmentVariable("Path", "$($env:Path);$InstallDir\bin", [EnvironmentVariableTarget]::Machine)

    Write-Host "BellSoft JDK 8 installed at $InstallDir"
    & java -version
}

# Function to install Apache Ant
function Install-Ant {
    $AntVersion = "1.10.15"
    $AntUrl = "https://downloads.apache.org/ant/binaries/apache-ant-$AntVersion-bin.zip"
    $InstallDir = "C:\Program Files\Ant"

    if ((Get-Command ant -ErrorAction SilentlyContinue) -and (& ant -version)) {
        Write-Host "Apache Ant is already installed."
        return
    }

    Write-Host "Installing Apache Ant..."
    $Archive = "$env:TEMP\apache-ant-$AntVersion-bin.zip"
    Invoke-WebRequest -Uri $AntUrl -OutFile $Archive
    Expand-Archive -Path $Archive -DestinationPath $InstallDir -Force

    # Set environment variables
    [Environment]::SetEnvironmentVariable("ANT_HOME", $InstallDir, [EnvironmentVariableTarget]::Machine)
    [Environment]::SetEnvironmentVariable("Path", "$($env:Path);$InstallDir\bin", [EnvironmentVariableTarget]::Machine)

    Write-Host "Apache Ant installed at $InstallDir"
    & ant -version
}

# Function to install Python 3.8
function Install-Python38 {
    $PythonVersion = "3.8.2"
    $PythonUrl = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
    $Installer = "$env:TEMP\python-$PythonVersion-amd64.exe"

    if ((Get-Command python3 -ErrorAction SilentlyContinue) -and (& python3 --version).Contains($PythonVersion)) {
        Write-Host "Python $PythonVersion is already installed"
        return
    }

    Write-Host "Installing Python $PythonVersion..."
    Invoke-WebRequest -Uri $PythonUrl -OutFile $Installer
    Start-Process -FilePath $Installer -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait

    Write-Host "Python $PythonVersion installed"
    & python3 --version
    & pip3 --version
}

# Function to install vcpkg
function Install-Vcpkg {
    $VcpkgDir = "$BuildDir\vcpkg"
    $VcpkgRepo = "https://github.com/microsoft/vcpkg.git"

    if ((Get-Command vcpkg -ErrorAction SilentlyContinue) -and (& vcpkg version)) {
        Write-Host "vcpkg is already installed."
        return
    }

    Write-Host "Installing vcpkg..."
    git clone $VcpkgRepo $VcpkgDir

    # Bootstrap vcpkg
    Set-Location -Path $VcpkgDir
    .\bootstrap-vcpkg.bat

    # Add vcpkg to PATH for the current session
    $env:Path += ";$VcpkgDir"

    [Environment]::SetEnvironmentVariable("VCPKG_ROOT", $VcpkgDir, [EnvironmentVariableTarget]::Machine)
    [Environment]::SetEnvironmentVariable("VCPKG_DISABLE_METRICS", "1", [EnvironmentVariableTarget]::Machine)
    [Environment]::SetEnvironmentVariable("VCPKG_DEFAULT_TRIPLET", "x64-windows-static", [EnvironmentVariableTarget]::Machine)
    [Environment]::SetEnvironmentVariable("VCPKG_BUILD_TYPE", "release", [EnvironmentVariableTarget]::Machine)

    Write-Host "vcpkg installed at $VcpkgDir"
    .\vcpkg.exe version
}

# Function to install Chocolatey
function Install-Choco {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "Chocolatey is already installed."
        return
    }

    Write-Host "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "Chocolatey installed successfully."
    } else {
        Write-Host "Failed to install Chocolatey."
        exit 1
    }
}

# Install dependencies
Install-BellSoftJDK8
Install-Ant
Install-Python38
Install-Vcpkg
Install-Choco

Write-Host "Preparing dependencies..."

# Install dependencies using Chocolatey (ensure Chocolatey is installed)
choco install -y git cmake python3 wget 7zip make ninja-build

# Install Python packages
& pip3 install numpy jinja2 --user
# Install vcpkg deps
& vcpkg install zlib libpng libjpeg-turbo libwebp tiff openjpeg

# Clone OpenCV repositories
Write-Host "Cloning OpenCV repositories..."
Set-Location -Path $BuildDir

if (-Not (Test-Path -Path "$BuildDir\opencv")) {
    git clone -b $OpenCVVersion --depth 1 https://github.com/opencv/opencv.git
}

if (-Not (Test-Path -Path "$BuildDir\opencv_contrib")) {
    git clone -b $OpenCVContribVersion --depth 1 https://github.com/opencv/opencv_contrib.git
}

# Configure and build OpenCV
Write-Host "Configuring and building OpenCV..."
$BuildOutputDir = "$BuildDir\build"
if (Test-Path -Path $BuildOutputDir) {
    Remove-Item -Recurse -Force -Path $BuildOutputDir
}
New-Item -ItemType Directory -Path $BuildOutputDir | Out-Null

cmake -G "Visual Studio 16 2019" `
    -A x64 `
    -D CMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" `
    -D VCPKG_TARGET_TRIPLET=$VCPKG_DEFAULT_TRIPLET `
    -D CMAKE_BUILD_TYPE=Release `
    -D CMAKE_INSTALL_PREFIX="$InstallDir" `
    -D OPENCV_EXTRA_MODULES_PATH="$BuildDir/opencv_contrib/modules" `
    -D ENABLE_PRECOMPILED_HEADERS=ON `
    -D BUILD_EXAMPLES=OFF `
    -D BUILD_DOCS=OFF `
    -S "$BuildDir\opencv" `
    -B $BuildOutputDir `
    -D BUILD_opencv_apps=OFF `
    -D BUILD_TESTS=OFF `
    -D BUILD_PERF_TESTS=OFF `
    -D OPENCV_ENABLE_JAVA=ON `
    -D BUILD_JAVA=ON `
    -D BUILD_opencv_java=ON `
    -D BUILD_opencv_java_bindings_generator=ON `
    -D BUILD_SHARED_LIBS=OFF `
    -D OPENCV_ENABLE_NONFREE=ON `
    -D BUILD_LIST=core,imgproc,highgui,imgcodecs,java,java_bindings_generator `
    -D WITH_QT=ON `
    -D ccitt=OFF `
    -D BUILD_ITT=OFF `
    -D WITH_ITT=OFF `
    -D WITH_VTK=OFF `
    -D WITH_OPENEXR=OFF `
    -D CV_TRACE=OFF `
    -D WITH_EIGEN=OFF `
    -D WITH_OPENCL=ON

cmake --build $BuildOutputDir --parallel $NumJobs
cmake --install $BuildOutputDir --prefix $InstallDir

Write-Host "OpenCV build and installation complete!"

tree $BuildDir