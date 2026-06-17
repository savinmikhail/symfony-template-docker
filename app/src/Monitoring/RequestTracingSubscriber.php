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
        $request->attributes->set(self::REQUEST_ID_ATTRIBUTE, $this->requestIdContext->assignNew());
        $request->attributes->set(self::REQUEST_STARTED_AT_ATTRIBUTE, microtime(true));
    }

    public function onResponse(ResponseEvent $event): void
    {
        if (!$event->isMainRequest()) {
            return;
        }

        $request = $event->getRequest();
        $requestId = $request->attributes->getString(self::REQUEST_ID_ATTRIBUTE, $this->requestIdContext->getCurrentRequestId() ?? '');
        if ('' !== $requestId) {
            $event->getResponse()->headers->set(self::RESPONSE_HEADER, $requestId);
        }

        $startedAt = $request->attributes->get(self::REQUEST_STARTED_AT_ATTRIBUTE);
        $durationMs = is_float($startedAt) || is_int($startedAt)
            ? (int) round((microtime(true) - (float) $startedAt) * 1000)
            : null;
        $route = is_string($request->attributes->get('_route')) ? $request->attributes->get('_route') : null;

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

        return in_array($path, self::OPERATIONAL_PATHS, true);
    }
}
