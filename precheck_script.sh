#!/bin/bash

# Pre-installation Check Script for n8n Self-hosted AI Starter Kit
# This script checks system requirements before installation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
WARNINGS=0

# Logging functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((CHECKS_FAILED++))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

section() {
    echo
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Version comparison function
version_ge() {
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# Convert bytes to human readable format
bytes_to_human() {
    local bytes=$1
    local gb=$((bytes / 1024 / 1024 / 1024))
    echo "${gb}GB"
}

# Main check function
main() {
    echo "=============================================================="
    echo "  n8n Self-hosted AI Starter Kit - Pre-installation Check"
    echo "=============================================================="
    
    # Operating System Check
    section "Operating System"
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="Linux"
        pass "Running on $OS"
        
        # Check Linux distribution
        if [ -f /etc/os-release ]; then
            DISTRO=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
            info "Distribution: $DISTRO"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macOS"
        pass "Running on $OS"
        
        # Check macOS version
        MACOS_VERSION=$(sw_vers -productVersion)
        info "Version: $MACOS_VERSION"
        
        # Check for Apple Silicon
        if [[ $(uname -m) == "arm64" ]]; then
            info "Apple Silicon detected"
        else
            info "Intel Mac detected"
        fi
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        OS="Windows"
        warn "Running on Windows. WSL2 is recommended for better performance."
        
        # Check if running in WSL
        if grep -qi microsoft /proc/version 2>/dev/null; then
            pass "Running in WSL"
        else
            warn "Consider using WSL2 for better Docker performance"
        fi
    else
        fail "Unsupported operating system: $OSTYPE"
        OS="Unknown"
    fi
    
    # Architecture Check
    ARCH=$(uname -m)
    info "Architecture: $ARCH"
    
    # Memory Check
    section "Memory"
    if [[ "$OS" == "Linux" ]]; then
        MEM_TOTAL=$(free -b | awk '/^Mem:/{print $2}')
        MEM_AVAILABLE=$(free -b | awk '/^Mem:/{print $7}')
        MEM_TOTAL_GB=$((MEM_TOTAL / 1024 / 1024 / 1024))
        MEM_AVAILABLE_GB=$((MEM_AVAILABLE / 1024 / 1024 / 1024))
        
        info "Total Memory: ${MEM_TOTAL_GB}GB"
        info "Available Memory: ${MEM_AVAILABLE_GB}GB"
        
        if [ "$MEM_TOTAL_GB" -ge 8 ]; then
            pass "Memory: ${MEM_TOTAL_GB}GB (Excellent)"
        elif [ "$MEM_TOTAL_GB" -ge 4 ]; then
            pass "Memory: ${MEM_TOTAL_GB}GB (Good)"
        else
            warn "Memory: ${MEM_TOTAL_GB}GB (Below recommended 4GB)"
        fi
        
    elif [[ "$OS" == "macOS" ]]; then
        MEM_TOTAL=$(sysctl -n hw.memsize)
        MEM_TOTAL_GB=$((MEM_TOTAL / 1024 / 1024 / 1024))
        
        info "Total Memory: ${MEM_TOTAL_GB}GB"
        
        if [ "$MEM_TOTAL_GB" -ge 8 ]; then
            pass "Memory: ${MEM_TOTAL_GB}GB (Excellent)"
        elif [ "$MEM_TOTAL_GB" -ge 4 ]; then
            pass "Memory: ${MEM_TOTAL_GB}GB (Good)"
        else
            warn "Memory: ${MEM_TOTAL_GB}GB (Below recommended 4GB)"
        fi
    fi
    
    # Disk Space Check
    section "Disk Space"
    DISK_AVAIL_BYTES=$(df . | tail -1 | awk '{print $4 * 1024}')
    DISK_AVAIL_GB=$((DISK_AVAIL_BYTES / 1024 / 1024 / 1024))
    
    info "Available Disk Space: ${DISK_AVAIL_GB}GB"
    
    if [ "$DISK_AVAIL_GB" -ge 20 ]; then
        pass "Disk Space: ${DISK_AVAIL_GB}GB (Excellent)"
    elif [ "$DISK_AVAIL_GB" -ge 10 ]; then
        pass "Disk Space: ${DISK_AVAIL_GB}GB (Good)"
    else
        warn "Disk Space: ${DISK_AVAIL_GB}GB (Below recommended 10GB)"
    fi
    
    # Docker Check
    section "Docker"
    if command_exists docker; then
        DOCKER_VERSION=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        info "Docker Version: $DOCKER_VERSION"
        
        if version_ge "$DOCKER_VERSION" "20.10.0"; then
            pass "Docker version is compatible"
        else
            fail "Docker version $DOCKER_VERSION is too old (minimum: 20.10.0)"
        fi
        
        # Check Docker daemon
        if docker info >/dev/null 2>&1; then
            pass "Docker daemon is running"
            
            # Get Docker info
            DOCKER_ROOT=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "N/A")
            info "Docker Root Dir: $DOCKER_ROOT"
            
        else
            fail "Docker daemon is not running"
        fi
        
        # Check Docker Compose
        if docker compose version >/dev/null 2>&1; then
            COMPOSE_VERSION=$(docker compose version --short)
            info "Docker Compose Version: $COMPOSE_VERSION"
            
            if version_ge "$COMPOSE_VERSION" "2.0.0"; then
                pass "Docker Compose version is compatible"
            else
                fail "Docker Compose version $COMPOSE_VERSION is too old (minimum: 2.0.0)"
            fi
        else
            fail "Docker Compose is not available"
        fi
    else
        fail "Docker is not installed"
    fi
    
    # Network Check
    section "Network Connectivity"
    
    # Check internet connectivity