#!/bin/bash

# Enhanced Installation Script for n8n Self-hosted AI Starter Kit
# This script automates the setup process with better error handling and user guidance

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="https://github.com/n8n-io/self-hosted-ai-starter-kit.git"
PROJECT_DIR="self-hosted-ai-starter-kit"
MIN_DOCKER_VERSION="20.10.0"
MIN_COMPOSE_VERSION="2.0.0"

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Version comparison function
version_ge() {
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# System requirements check
check_system_requirements() {
    log "Checking system requirements..."
    
    # Check if running on supported OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        OS="windows"
    else
        error "Unsupported operating system: $OSTYPE"
    fi
    
    info "Detected OS: $OS"
    
    # Check available memory (minimum 4GB recommended)
    if [[ "$OS" == "linux" ]]; then
        MEM_GB=$(free -g | awk '/^Mem:/{print $2}')
        if [ "$MEM_GB" -lt 4 ]; then
            warn "Less than 4GB RAM detected. Performance may be impacted."
        fi
    elif [[ "$OS" == "macos" ]]; then
        MEM_GB=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)}')
        if [ "$MEM_GB" -lt 4 ]; then
            warn "Less than 4GB RAM detected. Performance may be impacted."
        fi
    fi
    
    # Check available disk space (minimum 10GB recommended)
    DISK_AVAIL=$(df . | tail -1 | awk '{print int($4/1024/1024)}')
    if [ "$DISK_AVAIL" -lt 10 ]; then
        warn "Less than 10GB disk space available. Consider freeing up space."
    fi
}

# Check Docker installation and version
check_docker() {
    log "Checking Docker installation..."
    
    if ! command_exists docker; then
        error "Docker is not installed. Please install Docker first: https://docs.docker.com/get-docker/"
    fi
    
    DOCKER_VERSION=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if ! version_ge "$DOCKER_VERSION" "$MIN_DOCKER_VERSION"; then
        error "Docker version $DOCKER_VERSION is too old. Minimum required: $MIN_DOCKER_VERSION"
    fi
    
    info "Docker version: $DOCKER_VERSION ✓"
    
    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        error "Docker daemon is not running. Please start Docker."
    fi
    
    # Check Docker Compose
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_VERSION=$(docker compose version --short)
        if ! version_ge "$COMPOSE_VERSION" "$MIN_COMPOSE_VERSION"; then
            error "Docker Compose version $COMPOSE_VERSION is too old. Minimum required: $MIN_COMPOSE_VERSION"
        fi
        info "Docker Compose version: $COMPOSE_VERSION ✓"
    else
        error "Docker Compose is not available. Please install Docker Compose."
    fi
}

# Detect GPU capabilities
detect_gpu() {
    log "Detecting GPU capabilities..."
    
    GPU_TYPE="none"
    
    # Check for NVIDIA GPU
    if command_exists nvidia-smi; then
        if nvidia-smi >/dev/null 2>&1; then
            GPU_TYPE="nvidia"
            info "NVIDIA GPU detected"
            
            # Check for nvidia-container-runtime
            if docker info 2>/dev/null | grep -q nvidia; then
                info "NVIDIA Container Runtime detected ✓"
            else
                warn "NVIDIA Container Runtime not detected. GPU acceleration may not work."
                warn "Install nvidia-container-toolkit: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
            fi
        fi
    fi
    
    # Check for AMD GPU (Linux only)
    if [[ "$OS" == "linux" ]] && command_exists rocm-smi; then
        if rocm-smi >/dev/null 2>&1; then
            GPU_TYPE="amd"
            info "AMD GPU detected"
        fi
    fi
    
    # Check for Apple Silicon
    if [[ "$OS" == "macos" ]] && [[ $(uname -m) == "arm64" ]]; then
        GPU_TYPE="apple_silicon"
        info "Apple Silicon detected"
    fi
    
    if [[ "$GPU_TYPE" == "none" ]]; then
        info "No GPU detected or GPU not supported. Will use CPU mode."
    fi
    
    echo "$GPU_TYPE"
}

# Clone or update repository
setup_repository() {
    log "Setting up repository..."
    
    if [ -d "$PROJECT_DIR" ]; then
        warn "Directory $PROJECT_DIR already exists."
        read -p "Do you want to update it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cd "$PROJECT_DIR"
            git pull origin main
            cd ..
        fi
    else
        git clone "$REPO_URL" "$PROJECT_DIR"
    fi
    
    cd "$PROJECT_DIR"
}

# Configure environment
configure_environment() {
    log "Configuring environment..."
    
    # Create .env file if it doesn't exist
    if [ ! -f .env ]; then
        if [ -f .env.example ]; then
            cp .env.example .env
            info "Created .env file from example"
        else
            # Create basic .env file
            cat > .env << EOF
# n8n Configuration
N8N_PORT=5678
N8N_HOST=localhost

# Database Configuration
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# Qdrant Configuration
QDRANT_PORT=6333

# Ollama Configuration
OLLAMA_HOST=http://ollama:11434
EOF
            info "Created basic .env file"
        fi
    fi
    
    # Handle Apple Silicon specific configuration
    if [[ "$1" == "apple_silicon" ]]; then
        if grep -q "OLLAMA_HOST=http://ollama:11434" .env; then
            sed -i.bak 's|OLLAMA_HOST=http://ollama:11434|OLLAMA_HOST=http://host.docker.internal:11434|' .env
            info "Updated OLLAMA_HOST for Apple Silicon"
        fi
    fi
}

# Start services
start_services() {
    local gpu_type=$1
    log "Starting services..."
    
    # Determine Docker Compose profile
    case $gpu_type in
        "nvidia")
            PROFILE="gpu-nvidia"
            ;;
        "amd")
            PROFILE="gpu-amd"
            ;;
        "apple_silicon")
            PROFILE="default"
            ;;
        *)
            PROFILE="cpu"
            ;;
    esac
    
    info "Using profile: $PROFILE"
    
    # Pull images first
    if [[ "$PROFILE" == "default" ]]; then
        docker compose pull
    else
        docker compose --profile "$PROFILE" pull
    fi
    
    # Start services
    if [[ "$PROFILE" == "default" ]]; then
        docker compose up -d
    else
        docker compose --profile "$PROFILE" up -d
    fi
}

# Wait for services to be ready
wait_for_services() {
    log "Waiting for services to start..."
    
    # Wait for n8n
    info "Waiting for n8n to be ready..."
    timeout=300  # 5 minutes
    elapsed=0
    while ! curl -s http://localhost:5678/healthz >/dev/null 2>&1; do
        if [ $elapsed -ge $timeout ]; then
            error "Timeout waiting for n8n to start"
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done
    echo
    info "n8n is ready! ✓"
    
    # Wait for Qdrant
    info "Waiting for Qdrant to be ready..."
    timeout=120  # 2 minutes
    elapsed=0
    while ! curl -s http://localhost:6333/health >/dev/null 2>&1; do
        if [ $elapsed -ge $timeout ]; then
            warn "Qdrant may not be ready yet, but continuing..."
            break
        fi
        sleep 3
        elapsed=$((elapsed + 3))
        echo -n "."
    done
    echo
    if curl -s http://localhost:6333/health >/dev/null 2>&1; then
        info "Qdrant is ready! ✓"
    fi
}

# Post-installation setup
post_install_setup() {
    log "Running post-installation setup..."
    
    # Create shared directory if it doesn't exist
    mkdir -p shared
    info "Created shared directory for file operations"
    
    # Set appropriate permissions
    chmod 755 shared
    
    # Display status
    echo
    echo "==================== Installation Complete ===================="
    echo
    info "Services Status:"
    docker compose ps
    echo
    info "🚀 n8n is now accessible at: http://localhost:5678"
    info "📊 Qdrant dashboard at: http://localhost:6333/dashboard"
    echo
    info "Next Steps:"
    echo "1. Open http://localhost:5678 in your browser"
    echo "2. Complete the n8n setup wizard (first time only)"
    echo "3. Import workflows from: http://localhost:5678/workflow/srOnR8PAY3u4RSwb"
    echo "4. Start building your AI workflows!"
    echo
    info "Useful Commands:"
    echo "  - Stop services: docker compose down"
    echo "  - View logs: docker compose logs -f"
    echo "  - Update: docker compose pull && docker compose up -d"
    echo
    info "Need help? Check the documentation or visit: https://community.n8n.io"
    echo "=============================================================="
}

# Cleanup function
cleanup() {
    if [ $? -ne 0 ]; then
        error "Installation failed. Check the logs above for details."
        echo
        info "To clean up, run: docker compose down --volumes"
    fi
}

# Main installation function
main() {
    trap cleanup EXIT
    
    echo "=============================================================="
    echo "  n8n Self-hosted AI Starter Kit - Enhanced Installation"
    echo "=============================================================="
    echo
    
    check_system_requirements
    check_docker
    
    GPU_TYPE=$(detect_gpu)
    
    setup_repository
    configure_environment "$GPU_TYPE"
    start_services "$GPU_TYPE"
    wait_for_services
    post_install_setup
    
    trap - EXIT  # Remove trap on successful completion
}

# Handle special cases
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Handle command line arguments
    case "${1:-}" in
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --help, -h     Show this help message"
            echo "  --gpu-nvidia   Force NVIDIA GPU profile"
            echo "  --gpu-amd      Force AMD GPU profile"
            echo "  --cpu          Force CPU-only profile"
            echo "  --update       Update existing installation"
            exit 0
            ;;
        --gpu-nvidia)
            GPU_TYPE="nvidia"
            ;;
        --gpu-amd)
            GPU_TYPE="amd"
            ;;
        --cpu)
            GPU_TYPE="cpu"
            ;;
        --update)
            if [ -d "$PROJECT_DIR" ]; then
                cd "$PROJECT_DIR"
                docker compose pull
                docker compose up -d
                info "Update complete!"
                exit 0
            else
                error "Project directory not found. Run installation first."
            fi
            ;;
    esac
    
    main "$@"
fi