<?php

declare(strict_types=1);

namespace App\Shared\Telemetry;

use OpenTelemetry\API\Trace\SpanContext;
use OpenTelemetry\API\Trace\SpanContextInterface;
use OpenTelemetry\SDK\Common\Attribute\Attributes;
use OpenTelemetry\SDK\Common\Attribute\AttributesInterface;
use OpenTelemetry\SDK\Common\Instrumentation\InstrumentationScopeInterface;
use OpenTelemetry\SDK\Resource\ResourceInfo;
use OpenTelemetry\SDK\Trace\Link;
use OpenTelemetry\SDK\Trace\LinkInterface;
use OpenTelemetry\SDK\Trace\SpanDataInterface;
use OpenTelemetry\SDK\Trace\StatusData;
use OpenTelemetry\SDK\Trace\StatusDataInterface;
use Symfony\Component\DependencyInjection\Attribute\Exclude;

/** Strip trace state for every scope; filter automatic instrumentation metadata. */
#[Exclude]
final readonly class SafeSpanData implements SpanDataInterface
{
    private const ATTRIBUTES = [
        'http.request.method', 'http.response.status_code', 'http.route', 'error.type',
        'server.address', 'server.port', 'url.scheme', 'peer.service',
        'network.protocol.version', 'symfony.messenger.bus',
        'symfony.messenger.message', 'symfony.messenger.transport',
    ];

    public function __construct(private SpanDataInterface $span, private bool $filterMetadata = true) {}

    private static function withoutTraceState(SpanContextInterface $context): SpanContextInterface
    {
        return $context->isRemote()
            ? SpanContext::createFromRemoteParent(traceId: $context->getTraceId(), spanId: $context->getSpanId(), traceFlags: $context->getTraceFlags())
            : SpanContext::create(traceId: $context->getTraceId(), spanId: $context->getSpanId(), traceFlags: $context->getTraceFlags());
    }

    /** @return AttributesInterface<string, mixed> */
    public function getAttributes(): AttributesInterface
    {
        if (!$this->filterMetadata) {
            return $this->span->getAttributes();
        }

        return Attributes::create(attributes: array_intersect_key($this->span->getAttributes()->toArray(), array_flip(array: self::ATTRIBUTES)));
    }

    public function getStatus(): StatusDataInterface
    {
        if (!$this->filterMetadata) {
            return $this->span->getStatus();
        }

        return StatusData::create(code: $this->span->getStatus()->getCode());
    }

    public function getEvents(): array
    {
        return $this->filterMetadata ? [] : $this->span->getEvents();
    }

    public function getLinks(): array
    {
        return $this->filterMetadata ? [] : array_map(
            callback: static fn(LinkInterface $link): LinkInterface => new Link(context: self::withoutTraceState(context: $link->getSpanContext()), attributes: $link->getAttributes()),
            array: $this->span->getLinks(),
        );
    }

    public function getName(): string
    {
        return $this->span->getName();
    }

    public function getKind(): int
    {
        return $this->span->getKind();
    }

    public function getContext(): SpanContextInterface
    {
        return self::withoutTraceState(context: $this->span->getContext());
    }

    public function getParentContext(): SpanContextInterface
    {
        return self::withoutTraceState(context: $this->span->getParentContext());
    }

    public function getTraceId(): string
    {
        return $this->span->getTraceId();
    }

    public function getSpanId(): string
    {
        return $this->span->getSpanId();
    }

    public function getParentSpanId(): string
    {
        return $this->span->getParentSpanId();
    }

    public function getStartEpochNanos(): int
    {
        return $this->span->getStartEpochNanos();
    }

    public function getEndEpochNanos(): int
    {
        return $this->span->getEndEpochNanos();
    }

    public function hasEnded(): bool
    {
        return $this->span->hasEnded();
    }

    public function getInstrumentationScope(): InstrumentationScopeInterface
    {
        return $this->span->getInstrumentationScope();
    }

    public function getResource(): ResourceInfo
    {
        return $this->span->getResource();
    }

    public function getTotalDroppedEvents(): int
    {
        return $this->span->getTotalDroppedEvents();
    }

    public function getTotalDroppedLinks(): int
    {
        return $this->span->getTotalDroppedLinks();
    }
}
