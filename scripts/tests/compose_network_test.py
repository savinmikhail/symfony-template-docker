import importlib.util
import ipaddress
import json
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('compose_network', Path(__file__).resolve().parents[2] / 'docker/ensure-compose-network.py')
network = importlib.util.module_from_spec(spec)
spec.loader.exec_module(network)


def response(code=0, output='', error=''):
    return subprocess.CompletedProcess([], code, output, error)


class ComposeNetworkTest(unittest.TestCase):
    def test_existing_owned_network_is_reused(self):
        data = [{'Driver': 'bridge', 'Labels': {'com.docker.compose.project': 'test', 'com.docker.compose.network': 'default'}}]
        with patch.object(network, 'docker', return_value=response(output=json.dumps(data))) as docker:
            network.ensure('test')
            self.assertEqual(1, docker.call_count)

    def test_foreign_network_is_never_changed(self):
        with patch.object(network, 'docker', return_value=response(output='[{"Driver":"bridge","Labels":{}}]')) as docker:
            with self.assertRaisesRegex(RuntimeError, 'does not belong'):
                network.ensure('test')
            self.assertEqual(1, docker.call_count)

    def test_exhaustion_allocates_explicit_subnet_without_deleting_networks(self):
        replies = [response(1, error='No such network'),
                   response(1, error='all predefined address pools have been fully subnetted'),
                   response(output='id1'), response(output='[{"IPAM":{"Config":null}}, {"IPAM":{"Config":[{"Subnet":"10.240.0.0/24"}]}}]'),
                   response(output='new-id')]
        with patch.object(network, 'docker', side_effect=replies) as docker:
            network.ensure('test')
            command = docker.call_args.args
            self.assertIn('--subnet', command)
            self.assertNotIn('10.240.0.0/24', command)
            self.assertFalse(any('rm' in call.args or 'prune' in call.args for call in docker.call_args_list))

    def test_other_daemon_errors_do_not_trigger_subnet_fallback(self):
        with patch.object(network, 'docker', side_effect=[response(1, error='No such network'),
                         response(1, error='permission denied'), response(1, error='No such network')]) as docker:
            with self.assertRaisesRegex(RuntimeError, 'permission denied'):
                network.ensure('test')
            self.assertEqual(3, docker.call_count)

    def test_candidates_are_stable_and_skip_all_overlapping_networks(self):
        occupied = [ipaddress.ip_network('10.240.0.0/16'), ipaddress.ip_network('fd00::/64')]
        first = list(network.candidates('project', occupied, '10.240.0.0/12'))
        self.assertEqual(first, list(network.candidates('project', occupied, '10.240.0.0/12')))
        self.assertEqual(3840, len(first))
        self.assertTrue(all(not ipaddress.ip_network(n).overlaps(occupied[0]) for n in first))

    def test_exhausted_fallback_pool_reports_configuration_action(self):
        replies = [response(1, error='No such network'),
                   response(1, error='all predefined address pools have been fully subnetted'),
                   response(output='id1'), response(output='[{"IPAM":{"Config":[{"Subnet":"10.240.0.0/12"}]}}]')]
        with patch.object(network, 'docker', side_effect=replies):
            with self.assertRaisesRegex(RuntimeError, 'LOCAL_COMPOSE_SUBNET_POOL'):
                network.ensure('test')


if __name__ == '__main__':
    unittest.main()
