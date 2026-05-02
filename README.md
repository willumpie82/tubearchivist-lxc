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

**Note**: The default branch for the TubeArchivist fork is `develop`, not `master`.

### Pull Latest from Official Repository

```bash
cd tubearchivist
# Add upstream if not present
git remote add upstream https://github.com/tubearchivist/tubearchivist.git
git fetch upstream develop
git pull upstream develop
cd ..
```

### Track Develop Branch

```bash
cd tubearchivist
git checkout develop
git pull origin develop
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
# Create feature branch from official develop
git fetch upstream develop
git checkout -b fix/your-fix upstream/develop
# Apply and test your fix
git push origin fix/your-fix
# Create PR against tubearchivist/tubearchivist:develop
```

### Local Development (Track Develop)

For local testing and modifications on the develop branch:

```bash
cd tubearchivist
git checkout develop
git pull origin develop
# Make your changes
git add <files>
git commit -m "description"
# Test thoroughly
git push origin develop
```

### Update Submodule to Latest Develop

```bash
cd tubearchivist
git fetch origin develop
git pull origin develop
cd ..
git add tubearchivist
git commit -m "Update TubeArchivist submodule to latest develop"
git push origin master  # Push reference update to tubearchivist-lxc
```

## Submodule Management

### Add Upstream Remote (Track Official Repo)

```bash
cd tubearchivist
git remote add upstream https://github.com/tubearchivist/tubearchivist.git
git fetch upstream develop
# Now you can track official changes
```

### Update Submodule to Latest Develop

The TubeArchivist fork defaults to the `develop` branch (matching official repo):

```bash
cd tubearchivist
git pull origin develop  # pulls your fork's develop
# or
git pull upstream develop  # pulls official develop directly
cd ..
git add tubearchivist
git commit -m "Update TubeArchivist submodule"
git push origin master
```

### Switch Submodule Branch

```bash
cd tubearchivist
git checkout develop
cd ..
git add tubearchivist
git commit -m "Submodule: switch to develop branch"
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
