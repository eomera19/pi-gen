# Eomera Pi System Validation

This directory contains the complete validation system for your Eomera Pi build.

## Quick Start

```bash
# Run all validations
./validate-system.sh

# List available validations
./validate-system.sh --list

# Run specific stage validations
./validate-system.sh stage2
./validate-system.sh stage3

# Run specific step validation
./validate-system.sh stage3 50-desktop-core
```

## Directory Structure

```
validations/
├── validation-framework.sh          # Shared validation framework
├── stage2/                          # Stage 2 validations
│   └── 50-mdns-setup/
│       └── validations/
│           └── mdns.sh
├── stage3/                          # Stage 3 validations
│   ├── 50-desktop-core/
│   │   └── validations/
│   │       └── desktop.sh
│   └── 52-development-tools/
│       └── validations/
│           └── dev-tools.sh
└── stage4/                          # Stage 4 validations
    └── 07-additional-utils/
        └── validations/
            └── utils.sh
```

## Understanding Validation Results

- ✅ **PASS**: Check completed successfully
- ❌ **FAIL**: Check failed - requires attention
- ⚠️  **WARNING**: Non-critical issue detected
- ℹ️  **INFO**: Informational message

## Troubleshooting

If validations fail:

1. **Check the specific error messages** - they usually indicate what's wrong
2. **Run individual validations** to isolate issues
3. **Check system logs** for more details:
   ```bash
   journalctl -xe
   systemctl status <service-name>
   ```
4. **Verify configurations** mentioned in the failed checks

## Adding Custom Validations

To add your own validations:

1. Create a new `.sh` file in the appropriate `validations/` directory
2. The validation framework will be automatically sourced by validate-system.sh
3. Just use the framework functions directly (log_info, run_check, etc.)
4. Follow the template pattern for consistency

## Build Information

This validation system was automatically generated during the pi-gen build process.
Each validation corresponds to a build step that was executed during image creation.
