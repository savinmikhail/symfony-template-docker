<?php

declare(strict_types=1);

namespace App\Shared\Telemetry;

use OpenTelemetry\SDK\Common\Future\CancellationInterface;
use OpenTelemetry\SDK\Common\Future\FutureInterface;
use OpenTelemetry\SDK\Trace\SpanExporterInterface;
use Symfony\Component\DependencyInjection\Attribute\Exclude;

#[Exclude]
final readonly class SafeSpanExporter implements SpanExporterInterface
{
    public function __construct(private SpanExporterInterface $exporter) {}

    public function export(iterable $batch, ?CancellationInterface $cancellation = null): FutureInterface
    {
        $safe = [];
        foreach ($batch as $span) {
            $safe[] = new SafeSpanData(
                span: $span,
                filterMetadata: str_starts_with(haystack: $span->getInstrumentationScope()->getName(), needle: 'io.opentelemetry.contrib.php.symfony'),
            );
        }

        return $this->exporter->export(batch: $safe, cancellation: $cancellation);
    }

    public function shutdown(?CancellationInterface $cancellation = null): bool
    {
        return $this->exporter->shutdown(cancellation: $cancellation);
    }

    public function forceFlush(?CancellationInterface $cancellation = null): bool
    {
        return $this->exporter->forceFlush(cancellation: $cancellation);
    }
}
