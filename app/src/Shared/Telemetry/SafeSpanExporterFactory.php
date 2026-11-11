<?php

declare(strict_types=1);

namespace App\Shared\Telemetry;

use OpenTelemetry\Contrib\Otlp\SpanExporterFactory;
use OpenTelemetry\SDK\Trace\SpanExporter\SpanExporterFactoryInterface;
use OpenTelemetry\SDK\Trace\SpanExporterInterface;
use Symfony\Component\DependencyInjection\Attribute\Exclude;

#[Exclude]
final class SafeSpanExporterFactory implements SpanExporterFactoryInterface
{
    public function create(): SpanExporterInterface
    {
        $factory = new SpanExporterFactory();

        return new SafeSpanExporter(exporter: $factory->create());
    }
}
