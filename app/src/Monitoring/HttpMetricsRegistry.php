<?php

declare(strict_types=1);

namespace App\Monitoring;

use Symfony\Component\DependencyInjection\Attribute\Autowire;

final readonly class HttpMetricsRegistry
{
    private const BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0];
    private const KEY_SEPARATOR = "\x1F";

    public function __construct(
        #[Autowire('%kernel.project_dir%')]
        private string $projectDir,
    ) {
    }

    public function record(?string $route, string $method, int $statusCode, ?int $durationMs): void
    {
        $route = $this->normalizeRoute(route: $route);
        $method = $this->normalizeMethod(method: $method);
        $statusClass = $this->normalizeStatusClass(statusCode: $statusCode);
        $durationSeconds = null !== $durationMs ? max(0, $durationMs) / 1000 : 0.0;
        $seriesKey = $this->seriesKey(route: $route, method: $method, statusClass: $statusClass);

        $this->withState(mutate: static function (array $state) use ($seriesKey, $durationSeconds): array {
            $state['requests'][$seriesKey] = (int) ($state['requests'][$seriesKey] ?? 0) + 1;
            $state['duration_count'][$seriesKey] = (int) ($state['duration_count'][$seriesKey] ?? 0) + 1;
            $state['duration_sum'][$seriesKey] = (float) ($state['duration_sum'][$seriesKey] ?? 0.0) + $durationSeconds;

            foreach (self::BUCKETS as $bucket) {
                if ($durationSeconds <= $bucket) {
                    $bucketKey = sprintf('%s%s%s', $seriesKey, self::KEY_SEPARATOR, self::formatBucket(bucket: $bucket));
                    $state['duration_buckets'][$bucketKey] = (int) ($state['duration_buckets'][$bucketKey] ?? 0) + 1;
                }
            }

            $bucketKey = sprintf('%s%s+Inf', $seriesKey, self::KEY_SEPARATOR);
            $state['duration_buckets'][$bucketKey] = (int) ($state['duration_buckets'][$bucketKey] ?? 0) + 1;

            return $state;
        });
    }

    public function render(): string
    {
        $state = $this->readState();
        $lines = [
            '# HELP app_http_requests_total HTTP requests handled by Symfony, partitioned by low-cardinality route labels.',
            '# TYPE app_http_requests_total counter',
        ];

        ksort(array: $state['requests']);
        foreach ($state['requests'] as $seriesKey => $count) {
            $labels = $this->seriesLabels(seriesKey: $seriesKey);
            $lines[] = sprintf('app_http_requests_total{%s} %d', $this->renderLabels(labels: $labels), (int) $count);
        }

        $lines[] = '# HELP app_http_request_duration_seconds HTTP request duration histogram, partitioned by low-cardinality route labels.';
        $lines[] = '# TYPE app_http_request_duration_seconds histogram';

        ksort(array: $state['duration_count']);
        foreach ($state['duration_count'] as $seriesKey => $count) {
            $labels = $this->seriesLabels(seriesKey: $seriesKey);

            foreach (self::BUCKETS as $bucket) {
                $bucketLabel = self::formatBucket(bucket: $bucket);
                $bucketKey = sprintf('%s%s%s', $seriesKey, self::KEY_SEPARATOR, $bucketLabel);
                $lines[] = sprintf(
                    'app_http_request_duration_seconds_bucket{%s} %d',
                    $this->renderLabels(labels: $labels + ['le' => $bucketLabel]),
                    (int) ($state['duration_buckets'][$bucketKey] ?? 0),
                );
            }

            $bucketKey = sprintf('%s%s+Inf', $seriesKey, self::KEY_SEPARATOR);
            $lines[] = sprintf(
                'app_http_request_duration_seconds_bucket{%s} %d',
                $this->renderLabels(labels: $labels + ['le' => '+Inf']),
                (int) ($state['duration_buckets'][$bucketKey] ?? 0),
            );
            $lines[] = sprintf(
                'app_http_request_duration_seconds_sum{%s} %s',
                $this->renderLabels(labels: $labels),
                $this->formatFloat(value: (float) ($state['duration_sum'][$seriesKey] ?? 0.0)),
            );
            $lines[] = sprintf(
                'app_http_request_duration_seconds_count{%s} %d',
                $this->renderLabels(labels: $labels),
                (int) $count,
            );
        }

        return implode(separator: "\n", array: $lines)."\n";
    }

    private function withState(callable $mutate): void
    {
        $path = $this->statePath();
        $directory = \dirname(path: $path);
        if (!is_dir(filename: $directory) && !mkdir(directory: $directory, permissions: 0775, recursive: true) && !is_dir(filename: $directory)) {
            throw new \RuntimeException(message: sprintf('Unable to create metrics directory "%s".', $directory));
        }

        $handle = fopen(filename: $path, mode: 'c+');
        if (false === $handle) {
            throw new \RuntimeException(message: sprintf('Unable to open metrics state "%s".', $path));
        }

        try {
            flock(stream: $handle, operation: LOCK_EX);
            $contents = stream_get_contents(stream: $handle);
            $state = $this->decodeState(contents: false === $contents ? '' : $contents);
            $state = $mutate($state);
            rewind(stream: $handle);
            ftruncate(stream: $handle, size: 0);
            fwrite(stream: $handle, data: json_encode(value: $state, flags: JSON_THROW_ON_ERROR));
            fflush(stream: $handle);
        } finally {
            flock(stream: $handle, operation: LOCK_UN);
            fclose(stream: $handle);
        }
    }

    /**
     * @return array{requests: array<string, int>, duration_buckets: array<string, int>, duration_sum: array<string, float>, duration_count: array<string, int>}
     */
    private function readState(): array
    {
        $path = $this->statePath();
        if (!is_file(filename: $path)) {
            return $this->emptyState();
        }

        $contents = file_get_contents(filename: $path);

        return $this->decodeState(contents: false === $contents ? '' : $contents);
    }

    /**
     * @return array{requests: array<string, int>, duration_buckets: array<string, int>, duration_sum: array<string, float>, duration_count: array<string, int>}
     */
    private function decodeState(string $contents): array
    {
        if ('' === trim(string: $contents)) {
            return $this->emptyState();
        }

        try {
            $decoded = json_decode($contents, true, flags: JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            return $this->emptyState();
        }

        if (!is_array(value: $decoded)) {
            return $this->emptyState();
        }

        return [
            'requests' => $this->numericMap(value: $decoded['requests'] ?? []),
            'duration_buckets' => $this->numericMap(value: $decoded['duration_buckets'] ?? []),
            'duration_sum' => $this->floatMap(value: $decoded['duration_sum'] ?? []),
            'duration_count' => $this->numericMap(value: $decoded['duration_count'] ?? []),
        ];
    }

    /**
     * @return array{requests: array<string, int>, duration_buckets: array<string, int>, duration_sum: array<string, float>, duration_count: array<string, int>}
     */
    private function emptyState(): array
    {
        return [
            'requests' => [],
            'duration_buckets' => [],
            'duration_sum' => [],
            'duration_count' => [],
        ];
    }

    private function statePath(): string
    {
        return rtrim(string: $this->projectDir, characters: '/').'/var/metrics/http.json';
    }

    private function seriesKey(string $route, string $method, string $statusClass): string
    {
        return implode(separator: self::KEY_SEPARATOR, array: [$route, $method, $statusClass]);
    }

    /**
     * @return array{route: string, method: string, status_class: string}
     */
    private function seriesLabels(string $seriesKey): array
    {
        [$route, $method, $statusClass] = array_pad(array: explode(separator: self::KEY_SEPARATOR, string: $seriesKey, limit: 3), length: 3, value: 'unknown');

        return [
            'route' => $route,
            'method' => $method,
            'status_class' => $statusClass,
        ];
    }

    private function normalizeRoute(?string $route): string
    {
        $route = trim(string: (string) $route);
        if ('' === $route) {
            return 'unmatched';
        }

        return $this->normalizeLabelValue(value: $route);
    }

    private function normalizeMethod(string $method): string
    {
        $method = strtoupper(string: trim(string: $method));

        return '' !== $method ? $this->normalizeLabelValue(value: $method) : 'UNKNOWN';
    }

    private function normalizeStatusClass(int $statusCode): string
    {
        if ($statusCode < 100 || $statusCode > 599) {
            return 'unknown';
        }

        return sprintf('%dxx', intdiv(num1: $statusCode, num2: 100));
    }

    private function normalizeLabelValue(string $value): string
    {
        $normalized = preg_replace(pattern: '/[^A-Za-z0-9_.:-]+/', replacement: '_', subject: $value) ?? 'unknown';
        $normalized = trim(string: $normalized, characters: '_');

        return '' !== $normalized ? substr(string: $normalized, offset: 0, length: 100) : 'unknown';
    }

    /**
     * @param array<string, string> $labels
     */
    private function renderLabels(array $labels): string
    {
        $parts = [];
        foreach ($labels as $name => $value) {
            $parts[] = sprintf('%s="%s"', $name, str_replace(search: ['\\', "\n", '"'], replace: ['\\\\', '\\n', '\\"'], subject: $value));
        }

        return implode(separator: ',', array: $parts);
    }

    /**
     * @return array<string, int>
     */
    private function numericMap(mixed $value): array
    {
        if (!is_array(value: $value)) {
            return [];
        }

        $result = [];
        foreach ($value as $key => $item) {
            $result[(string) $key] = max(0, (int) $item);
        }

        return $result;
    }

    /**
     * @return array<string, float>
     */
    private function floatMap(mixed $value): array
    {
        if (!is_array(value: $value)) {
            return [];
        }

        $result = [];
        foreach ($value as $key => $item) {
            $result[(string) $key] = max(0.0, (float) $item);
        }

        return $result;
    }

    private static function formatBucket(float $bucket): string
    {
        return rtrim(string: rtrim(string: sprintf('%.3F', $bucket), characters: '0'), characters: '.');
    }

    private function formatFloat(float $value): string
    {
        return rtrim(string: rtrim(string: sprintf('%.6F', $value), characters: '0'), characters: '.') ?: '0';
    }
}
