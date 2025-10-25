# Docker Compose File Selection Guide

This directory contains **7 different Docker Compose configurations** for different hardware and LLM backend preferences. Choose the right file for your setup.

---

## Quick Decision Tree

```
Do you have a GPU?
├─ No → Use docker-compose-anythingllm.yml (cloud other hosted LLM, no "local" inference)
│  └─ Still want local inference → docker-compose-ollama-cpu.yml Yikes!
└─ Yes → What kind?
    ├─ NVIDIA → Want both backends?
    │   ├─ Yes → docker-compose-full-nvidia.yml (recommended)
    │   └─ No → docker-compose-ollama-nvidia.yml (local only)
    └─ AMD → Want both backends?
        ├─ Yes → docker-compose-full-amd.yml (recommended)
        └─ No → docker-compose-ollama-amd.yml (local only)
```

---

## File Reference

| File | GPU | Backends | Best For |
|------|-----|----------|----------|
| **docker-compose-ollama-nvidia.yml** | ✅ NVIDIA | Ollama only | Privacy-focused users with NVIDIA GPU |
| **docker-compose-ollama-amd.yml** | ✅ AMD | Ollama only | Privacy-focused users with AMD GPU |
| **docker-compose-ollama-cpu.yml** | ❌ CPU | Ollama only | Testing/development (very slow) |
| **docker-compose-anythingllm.yml** | ❌ None | AnythingLLM only | Cloud LLM users, no local GPU |
| **docker-compose-full-nvidia.yml** | ✅ NVIDIA | Both (Ollama primary) | **Recommended** for NVIDIA users |
| **docker-compose-full-amd.yml** | ✅ AMD | Both (Ollama primary) | **Recommended** for AMD users |
| **docker-compose-full-cpu.yml** | ❌ CPU | Both (likely fallback) | Not recommended, use AnythingLLM instead |

---

## Detailed Configurations

### 1. Ollama Only - NVIDIA GPU
**File:** `docker-compose-ollama-nvidia.yml`

**Hardware Requirements:**
- NVIDIA GPU with 6GB+ VRAM
- NVIDIA Container Toolkit installed
- 16GB+ system RAM

**What You Get:**
- Fast, private, local LLM inference
- No API costs
- No cloud dependencies
- Best JSON reliability

**Setup:**
```bash
# Start the stack
docker compose -f docker-compose-ollama-nvidia.yml up -d

# Pull models
docker exec -it ollama ollama pull qwen2.5:7b-instruct
docker exec -it ollama ollama pull nomic-embed-text:v1.5

# Place your resume
mkdir -p ./data/resume
cp ~/my-resume.txt ./data/resume/resume.txt

# Configure .env (see .env.example)
nano .env

# Restart
docker compose -f docker-compose-ollama-nvidia.yml restart jobcollector
```

---

### 2. Ollama Only - AMD GPU
**File:** `docker-compose-ollama-amd.yml`

**Hardware Requirements:**
- AMD RX 6000/7000 series or newer
- ROCm support enabled
- 16GB+ system RAM

**What You Get:**
- Same benefits as NVIDIA version
- May be slightly slower depending on model

**Important:** Set `HSA_OVERRIDE_GFX_VERSION` in the compose file to match your GPU. Common values:
- RX 6800/6900: `10.3.0`
- RX 7900: `11.0.0`

**Setup:**
```bash
# Edit compose file to set HSA_OVERRIDE_GFX_VERSION
nano docker-compose-ollama-amd.yml

# Start the stack
docker compose -f docker-compose-ollama-amd.yml up -d

# Follow same setup steps as NVIDIA version above
```

---

### 3. Ollama Only - CPU
**File:** `docker-compose-ollama-cpu.yml`

**Hardware Requirements:**
- 8+ CPU cores
- 16GB+ RAM
- Patience (4-8 minutes per job)

**What You Get:**
- Works without GPU
- Privacy benefits
- **Very slow** - not recommended for production

**Note:** This is configured to use smaller models (3B parameters) by default. Even then, expect 4-8 minutes per job scored.

**Setup:**
```bash
docker compose -f docker-compose-ollama-cpu.yml up -d
# Same setup as GPU versions, but use smaller model
docker exec -it ollama ollama pull llama3.2:3b-instruct-q6_K
```

---

### 4. AnythingLLM Only
**File:** `docker-compose-anythingllm.yml`

**Hardware Requirements:**
- Any CPU (no GPU needed)
- 8GB+ RAM
- API key from OpenAI, Anthropic, or other provider

**What You Get:**
- Fast cloud inference
- Multiple provider options
- Easy setup
- Costs per API call

**Best For:**
- Users without GPU
- Testing/development
- Low-volume usage
- Access to latest models (GPT-4, Claude, etc.)

**Setup:**
```bash
# Start the stack
docker compose -f docker-compose-anythingllm.yml up -d

# Open UI
xdg-open http://localhost:3001  # Linux
open http://localhost:3001      # macOS
start http://localhost:3001     # Windows

# Follow UI setup wizard:
# 1. Choose your LLM provider
# 2. Enter API key
# 3. Create workspace named "job-searching"
# 4. Upload resume
# 5. Configure system prompt (see main README)
# 6. Generate API key
# 7. Update .env with workspace slug and API key
# 8. Restart jobcollector

docker compose -f docker-compose-anythingllm.yml restart jobcollector
```

---

### 5. Both Backends - NVIDIA GPU (Recommended)
**File:** `docker-compose-full-nvidia.yml`

**Hardware Requirements:**
- NVIDIA GPU with 6GB+ VRAM
- NVIDIA Container Toolkit
- API key for fallback (optional but recommended)

**What You Get:**
- **Primary:** Fast local Ollama inference
- **Fallback:** AnythingLLM if Ollama fails
- Best of both worlds

**Why Both?**
- Ollama is tried first (fast, free, private)
- If Ollama crashes or timeouts, AnythingLLM automatically takes over
- Maximum reliability

**Setup:**
```bash
docker compose -f docker-compose-full-nvidia.yml up -d

# Set up Ollama
docker exec -it ollama ollama pull qwen2.5:7b-instruct
docker exec -it ollama ollama pull nomic-embed-text:v1.5
mkdir -p ./data/resume
cp ~/my-resume.txt ./data/resume/resume.txt

# Set up AnythingLLM (in browser)
xdg-open http://localhost:3001
# Follow setup wizard (see AnythingLLM-only section above)

# Update .env with BOTH sets of credentials
nano .env

# Restart
docker compose -f docker-compose-full-nvidia.yml restart jobcollector
```

---

### 6. Both Backends - AMD GPU
**File:** `docker-compose-full-amd.yml`

Same as NVIDIA version above, but uses `ollama/ollama:rocm` image. Remember to set `HSA_OVERRIDE_GFX_VERSION`.

---

### 7. Both Backends - CPU
**File:** `docker-compose-full-cpu.yml`

**Not Recommended.** Ollama on CPU is so slow that AnythingLLM will almost always be used. If you don't have a GPU, use `docker-compose-anythingllm.yml` instead.

---

## Environment Variable Guide

All compose files use the same `.env` file, but some variables are ignored depending on backend:

| Variable | Ollama-Only | AnythingLLM-Only | Both |
|----------|-------------|------------------|------|
| `OLLAMA_BASE` | ✅ Required | ❌ Ignored | ✅ Required |
| `SCORER_MODEL` | ✅ Required | ❌ Ignored | ✅ Required |
| `CANDIDATE_RESUME_PATH` | ✅ Required | ❌ Ignored | ✅ Required |
| `MUST_HAVES` | ✅ Required | ❌ Ignored | ✅ Required |
| `NICE_TO_HAVES` | ✅ Required | ❌ Ignored | ✅ Required |
| `ANLLM_API_KEY` | ❌ Ignored | ✅ Required | ⚠️ Optional (fallback) |
| `ANLLM_API_WORKSPACE` | ❌ Ignored | ✅ Required | ⚠️ Optional (fallback) |
| `SEARCH_TERMS` | ✅ Required | ✅ Required | ✅ Required |
| `LOCATION` | ✅ Required | ✅ Required | ✅ Required |

**See `.env.example` for complete reference.**

---

## Switching Between Configurations

To change configurations:

```bash
# Stop current stack
docker compose down

# Start new stack
docker compose -f docker-compose-NEW-FILE.yml up -d
```

**Data persistence:** All configurations use the same `DATA_DIR`, so your job data is preserved when switching.

---

## Performance Comparison

| Configuration | Speed (per job) | Privacy | Cost | Reliability |
|---------------|-----------------|---------|------|-------------|
| Ollama NVIDIA | ~4 seconds | ⭐⭐⭐⭐⭐ | Free | ⭐⭐⭐⭐ |
| Ollama AMD | ~6 seconds | ⭐⭐⭐⭐⭐ | Free | ⭐⭐⭐⭐ |
| Ollama CPU | ~5 minutes | ⭐⭐⭐⭐⭐ | Free | ⭐⭐⭐ |
| AnythingLLM (cloud) | ~2 seconds | ⭐ | $0.01-0.10/job | ⭐⭐⭐⭐⭐ |
| Both (NVIDIA) | ~4 seconds* | ⭐⭐⭐⭐⭐ | Free* | ⭐⭐⭐⭐⭐ |
| Both (AMD) | ~6 seconds* | ⭐⭐⭐⭐⭐ | Free* | ⭐⭐⭐⭐⭐ |

\* Uses Ollama first; falls back to AnythingLLM only if needed

---

## Troubleshooting

### "No LLM service available"

**Check which services are running:**
```bash
docker compose ps
```

**For Ollama:**
```bash
# Verify Ollama is reachable
docker exec jobcollector curl http://ollama:11434/api/tags

# Check logs
docker logs ollama
```

**For AnythingLLM:**
```bash
# Verify AnythingLLM is reachable
docker exec jobcollector curl http://anythingllm:3001/api/ping

# Check logs
docker logs anythingllm
```

### GPU Not Detected (NVIDIA)

```bash
# Verify NVIDIA Container Toolkit
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi

# If that fails, install toolkit:
# https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html
```

### GPU Not Detected (AMD)

```bash
# Verify ROCm
docker run --rm --device=/dev/kfd --device=/dev/dri rocm/pytorch:latest rocm-smi

# Check GPU is in supported list:
# https://rocm.docs.amd.com/projects/install-on-linux/en/latest/reference/system-requirements.html
```

### Models Not Downloading

```bash
# Check disk space
df -h

# Manually pull with progress
docker exec -it ollama ollama pull qwen2.5:7b-instruct

# If timeout, increase timeout in compose file
```

---

## Recommended Configurations by Use Case

| Use Case | Recommended File | Why |
|----------|------------------|-----|
| **Production job hunting** | `docker-compose-full-nvidia.yml` | Fast, reliable, private with fallback |
| **Privacy-focused** | `docker-compose-ollama-nvidia.yml` | 100% local, no cloud dependencies |
| **Testing/development** | `docker-compose-anythingllm.yml` | Fast setup, pay-as-you-go |
| **Budget constraint** | `docker-compose-ollama-nvidia.yml` | Free after GPU purchase |
| **No GPU available** | `docker-compose-anythingllm.yml` | Only viable option without GPU |
| **Maximum reliability** | `docker-compose-full-nvidia.yml` | Automatic fallback on failure |

---

**Questions?** See main [README.md](../README.md) or open an issue.