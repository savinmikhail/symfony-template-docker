<?php

declare(strict_types=1);

namespace App\Monitoring;

use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpKernel\Event\RequestEvent;
use Symfony\Component\HttpKernel\Event\ResponseEvent;
use Symfony\Component\HttpKernel\KernelEvents;

final readonly class RequestTracingSubscriber implements EventSubscriberInterface
{
    public const REQUEST_ID_ATTRIBUTE = '_request_id';
    private const REQUEST_STARTED_AT_ATTRIBUTE = '_request_started_at';
    private const RESPONSE_HEADER = 'X-Request-Id';
    private const OPERATIONAL_PATHS = ['/metrics', '/fpm-ping', '/fpm-status'];

    public function __construct(
        private RequestIdContext $requestIdContext,
        private HttpMetricsRegistry $httpMetricsRegistry,
    ) {
    }

    public static function getSubscribedEvents(): array
    {
        return [
            KernelEvents::REQUEST => ['onRequest', 2048],
            KernelEvents::RESPONSE => ['onResponse', -2048],
        ];
    }

    public function onRequest(RequestEvent $event): void
    {
        if (!$event->isMainRequest()) {
            return;
        }

        $request = $event->getRequest();
        $request->attributes->set(key: self::REQUEST_ID_ATTRIBUTE, value: $this->requestIdContext->assignNew());
        $request->attributes->set(key: self::REQUEST_STARTED_AT_ATTRIBUTE, value: microtime(as_float: true));
    }

    public function onResponse(ResponseEvent $event): void
    {
        if (!$event->isMainRequest()) {
            return;
        }

        $request = $event->getRequest();
        $requestId = $request->attributes->getString(key: self::REQUEST_ID_ATTRIBUTE, default: $this->requestIdContext->getCurrentRequestId() ?? '');
        if ('' !== $requestId) {
            $event->getResponse()->headers->set(key: self::RESPONSE_HEADER, values: $requestId);
        }

        $startedAt = $request->attributes->get(key: self::REQUEST_STARTED_AT_ATTRIBUTE);
        $durationMs = is_float(value: $startedAt) || is_int(value: $startedAt)
            ? (int) round(num: (microtime(as_float: true) - (float) $startedAt) * 1000)
            : null;
        $route = is_string(value: $request->attributes->get(key: '_route')) ? $request->attributes->get(key: '_route') : null;

        if ($this->isOperationalRequest(path: $request->getPathInfo(), route: $route)) {
            return;
        }

        $this->httpMetricsRegistry->record(
            route: $route,
            method: $request->getMethod(),
            statusCode: $event->getResponse()->getStatusCode(),
            durationMs: $durationMs,
        );
    }

    private function isOperationalRequest(string $path, ?string $route): bool
    {
        if ('metrics_prometheus' === $route) {
            return true;
        }

        return in_array(needle: $path, haystack: self::OPERATIONAL_PATHS, strict: true);
    }
}
