#!/bin/bash

# Quick Setup Script - No GitHub Repository Required
# This downloads and sets up everything locally

echo "=============================================================="
echo "  n8n Self-hosted AI Starter Kit - Quick Setup"
echo "=============================================================="

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Step 1: Clone the original repository
log "Cloning n8n self-hosted AI starter kit..."
if [ -d "self-hosted-ai-starter-kit" ]; then
    info "Directory already exists, updating..."
    cd self-hosted-ai-starter-kit
    git pull origin main
else
    git clone https://github.com/n8n-io/self-hosted-ai-starter-kit.git
    cd self-hosted-ai-starter-kit
fi

# Step 2: Download enhanced installation script
log "Setting up enhanced installation script..."
cat > install.sh << 'INSTALL_SCRIPT_EOF'
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
MIN_DOCKER_VERSION="20.10.0"
MIN_COMPOSE_VERSION="2.0.0"

# Logging functions
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

# Configure environment
configure_environment() {
    log "Configuring environment..."
    
    # Create .env file if it doesn't exist
    if [ ! -f .env ]; then
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
        info "Created .env file with secure defaults"
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
    echo "3. Import workflows and start building!"
    echo
    info "Useful Commands:"
    echo "  - Stop services: docker compose down"
    echo "  - View logs: docker compose logs -f"
    echo "  - Update: docker compose pull && docker compose up -d"
    echo "=============================================================="
}

# Main installation function
main() {
    echo "=============================================================="
    echo "  n8n Self-hosted AI Starter Kit - Enhanced Installation"
    echo "=============================================================="
    echo
    
    check_system_requirements
    check_docker
    
    GPU_TYPE=$(detect_gpu)
    
    configure_environment "$GPU_TYPE"
    start_services "$GPU_TYPE"
    wait_for_services
    post_install_setup
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --gpu-nvidia   Force NVIDIA GPU profile"
        echo "  --gpu-amd      Force AMD GPU profile"
        echo "  --cpu          Force CPU-only profile"
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
esac

main "$@"
INSTALL_SCRIPT_EOF

# Make the script executable
chmod +x install.sh

# Step 3: Create a simple usage guide
log "Creating usage guide..."
cat > ENHANCED_USAGE.md << 'USAGE_EOF'
# Enhanced n8n AI Starter Kit - Quick Usage

## 🚀 Quick Start

1. **Run the enhanced installer:**
   ```bash
   ./install.sh
   ```

2. **Or choose specific GPU mode:**
   ```bash
   ./install.sh --gpu-nvidia  # For NVIDIA GPUs
   ./install.sh --gpu-amd     # For AMD GPUs  
   ./install.sh --cpu         # CPU-only mode
   ```

3. **Access n8n:**
   Open http://localhost:5678 in your browser

## 🛠️ Management Commands

- **Stop services:** `docker compose down`
- **Start services:** `docker compose up -d`
- **View logs:** `docker compose logs -f`
- **Update:** `docker compose pull && docker compose up -d`

## 🆘 Need Help?
- Check logs: `docker compose logs`
- Visit: https://community.n8n.io
USAGE_EOF

# Step 4: Done!
log "Setup complete!"
echo
info "Enhanced installation is ready! You can now run:"
echo "  ./install.sh"
echo
info "Or with specific options:"
echo "  ./install.sh --gpu-nvidia"
echo "  ./install.sh --gpu-amd" 
echo "  ./install.sh --cpu"
echo
info "Check ENHANCED_USAGE.md for more details."
