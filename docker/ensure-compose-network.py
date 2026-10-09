#!/usr/bin/env python3
"""Create only this Compose project's default network; recover exhausted IPAM pools."""
import argparse
import hashlib
import ipaddress
import json
import os
import subprocess


def docker(*args):
    return subprocess.run(['docker', *args], capture_output=True, text=True, timeout=30)


def owned_network(project):
    result = docker('network', 'inspect', f'{project}_default')
    if result.returncode:
        if 'No such network' in result.stderr or 'not found' in result.stderr:
            return False
        raise RuntimeError(result.stderr.strip())
    network = json.loads(result.stdout)[0]
    labels = network.get('Labels') or {}
    if (network['Driver'] != 'bridge' or labels.get('com.docker.compose.project') != project
            or labels.get('com.docker.compose.network') != 'default'):
        raise RuntimeError('Existing default network does not belong to this Compose project')
    return True


def candidates(project, occupied, pool):
    networks = list(ipaddress.ip_network(pool).subnets(new_prefix=24))
    offset = int.from_bytes(hashlib.sha256(project.encode()).digest()[:4], 'big') % len(networks)
    for step in range(len(networks)):
        subnet = networks[(offset + step) % len(networks)]
        if not any(subnet.version == other.version and subnet.overlaps(other) for other in occupied):
            yield str(subnet)


def ensure(project, pool='10.240.0.0/12'):
    if owned_network(project):
        return
    args = ['network', 'create', '--driver', 'bridge',
            '--label', f'com.docker.compose.project={project}',
            '--label', 'com.docker.compose.network=default']
    result = docker(*args, f'{project}_default')
    if result.returncode == 0:
        return
    if 'all predefined address pools have been fully subnetted' not in result.stderr:
        if owned_network(project):  # Concurrent Task may have created the same project network.
            return
        raise RuntimeError(result.stderr.strip())
    listing = docker('network', 'ls', '-q')
    if listing.returncode:
        raise RuntimeError(listing.stderr.strip())
    inspection = docker('network', 'inspect', *listing.stdout.split())
    if inspection.returncode:
        raise RuntimeError(inspection.stderr.strip())
    occupied = [ipaddress.ip_network(c['Subnet']) for n in json.loads(inspection.stdout)
                for c in (n.get('IPAM', {}).get('Config') or []) if c.get('Subnet')]
    for subnet in candidates(project, occupied, pool):
        result = docker(*args, '--subnet', subnet, f'{project}_default')
        if result.returncode == 0:
            print(f'Compose network {project}_default: fallback subnet {subnet}')
            return
        if owned_network(project):
            return
        if 'overlap' not in result.stderr.lower():
            raise RuntimeError(result.stderr.strip())
    raise RuntimeError('No free fallback Compose subnet; configure LOCAL_COMPOSE_SUBNET_POOL')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project')
    args = parser.parse_args()
    ensure(args.project, os.environ.get('LOCAL_COMPOSE_SUBNET_POOL', '10.240.0.0/12'))
