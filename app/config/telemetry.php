<?php

declare(strict_types=1);

use App\Shared\Telemetry\SafeSpanExporterFactory;
use OpenTelemetry\SDK\Registry;

Registry::registerSpanExporterFactory('otlp', SafeSpanExporterFactory::class, true);
