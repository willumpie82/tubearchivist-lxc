# TubeArchivist LXC Setup

Custom TubeArchivist setup tailored for LXC container deployment with additional services, helpers, and configuration for production use.

## Repository Structure

```
tubearchivist-lxc/
├── tubearchivist/          # Official TubeArchivist (git submodule)
│   ├── backend/
│   ├── frontend/
│   └── ...
├── docs/                   # Documentation
│   ├── DEPLOYMENT_COMPLETE.md
│   ├── FIXES_APPLIED.md
│   ├── SPECIFICATION.md
│   └── TUBEARCHIVIST_CONFIG.md
├── helpers/                # Helper scripts
│   ├── ta-helper-run.sh
│   └── ta-helper-simple.py
├── tubearchivist_setup_ubuntu.sh      # LXC container setup
├── upgrade_tubearchivist.sh           # Upgrade helper
└── README.md
```

## Setup

### Clone with Submodule

```bash
git clone https://github.com/willumpie82/tubearchivist-lxc.git
cd tubearchivist-lxc
git submodule update --init --recursive
```

### Initial LXC Container Setup

```bash
# Make setup script executable
chmod +x tubearchivist_setup_ubuntu.sh

# Run setup (requires root or sudo)
sudo ./tubearchivist_setup_ubuntu.sh
```

## Updating TubeArchivist

### Pull Latest from Official Repository

```bash
cd tubearchivist
git fetch upstream  # if upstream remote exists
git pull origin develop  # or track develop branch
cd ..
```

### Upgrade Installation

```bash
./upgrade_tubearchivist.sh
```

## Fixes Applied

This setup includes fixes for video extraction issues:

1. **Video Ordering**: Removed timestamp sorting that caused TypeError with None values
2. **youtube_id Field Mapping**: Maps yt-dlp's `id` field to `youtube_id`
3. **Elasticsearch Error Handling**: Graceful handling of missing indices

See [FIXES_APPLIED.md](docs/FIXES_APPLIED.md) for details.

## Configuration

See [TUBEARCHIVIST_CONFIG.md](docs/TUBEARCHIVIST_CONFIG.md) for environment and service configuration.

## Contributing

### Submit Fixes to Official Repository

To contribute fixes back to the official TubeArchivist project:

```bash
cd tubearchivist
git checkout develop
git pull upstream develop
# Apply your fix
git push origin <your-branch>
# Create PR on GitHub
```

### Local Development

For local testing and modifications:

```bash
cd tubearchivist
# Make your changes
git add <files>
git commit -m "description"
# Test thoroughly
```

## Submodule Management

### Add Upstream Remote (for official repo tracking)

```bash
cd tubearchivist
git remote add upstream https://github.com/tubearchivist/tubearchivist.git
git fetch upstream
```

### Update Submodule Commit Reference

```bash
cd tubearchivist
git checkout <branch>
cd ..
git add tubearchivist
git commit -m "Update TubeArchivist submodule to <commit-hash>"
git push
```

## Documentation

- [DEPLOYMENT_COMPLETE.md](docs/DEPLOYMENT_COMPLETE.md) - Deployment notes
- [FIXES_APPLIED.md](docs/FIXES_APPLIED.md) - Technical details of fixes
- [SPECIFICATION.md](docs/SPECIFICATION.md) - System specifications
- [TUBEARCHIVIST_CONFIG.md](docs/TUBEARCHIVIST_CONFIG.md) - Configuration guide

## License

This setup wrapper is provided as-is. The official TubeArchivist project retains its own license.

## Author

Willem Oldemans <willem@oldemans.nl>

---

**Note**: This repository is a custom setup wrapper. The official TubeArchivist code is maintained as a submodule. For issues with TubeArchivist itself, refer to the [official repository](https://github.com/tubearchivist/tubearchivist).
