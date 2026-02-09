#!/usr/bin/env python3
"""
Generate GitHub Actions matrix from ubuntu-versions.yml
Reads the centralized configuration and outputs JSON for workflow matrix.
"""

import argparse
import json
import sys
import yaml
from pathlib import Path

def load_ubuntu_versions(config_file):
    """Load and parse ubuntu-versions.yml"""
    with open(config_file, 'r') as f:
        config = yaml.safe_load(f)
    return config

def generate_matrix(config, include_upcoming=False):
    """Generate matrix from supported_versions (and optionally upcoming_versions) in config"""
    matrix = []
    
    # Add supported versions
    for version in config.get('supported_versions', []):
        entry = {
            'ubuntu_version': version['version'],
            'ubuntu_lts': version.get('lts', version['version']),
            'image_offer': version['image_offer'],
            'image_sku': version['image_sku'],
            'python_expected': version['python'],
            'continue_on_error': version.get('status') != 'active'  # Only active versions fail build
        }
        matrix.append(entry)
    
    # Add upcoming versions if requested
    if include_upcoming:
        for version in config.get('upcoming_versions', []):
            # Use pre_release_image if available, otherwise use standard image
            if 'pre_release_image' in version:
                image_offer = version['pre_release_image']['offer']
                image_sku = version['pre_release_image']['sku']
            else:
                image_offer = version['image_offer']
                image_sku = version['image_sku']
            
            entry = {
                'ubuntu_version': version['version'],
                'ubuntu_lts': version.get('lts', version['version']),
                'image_offer': image_offer,
                'image_sku': image_sku,
                'python_expected': version['python'],
                'continue_on_error': True  # Upcoming versions always allow failure
            }
            matrix.append(entry)
    
    return matrix

def main():
    parser = argparse.ArgumentParser(
        description='Generate GitHub Actions matrix from ubuntu-versions.yml'
    )
    parser.add_argument(
        '--include-upcoming',
        action='store_true',
        help='Include upcoming_versions (pre-release) in matrix'
    )
    args = parser.parse_args()
    
    script_dir = Path(__file__).parent
    config_file = script_dir.parent / 'ubuntu-versions.yml'
    
    if not config_file.exists():
        print(f"Error: {config_file} not found", file=sys.stderr)
        sys.exit(1)
    
    try:
        config = load_ubuntu_versions(config_file)
        matrix = generate_matrix(config, include_upcoming=args.include_upcoming)
        
        # Output as GitHub Actions matrix JSON
        output = {'include': matrix}
        print(json.dumps(output))
        
    except Exception as e:
        print(f"Error generating matrix: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
