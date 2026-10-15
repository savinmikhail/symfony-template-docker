<?php

declare(strict_types=1);

namespace App\Shared\Http;

use Psr\Log\LoggerInterface;
use Symfony\Component\DependencyInjection\Attribute\AsDecorator;
use Symfony\Component\DependencyInjection\Attribute\AutowireDecorated;
use Symfony\Component\HttpClient\AsyncDecoratorTrait;
use Symfony\Component\HttpClient\Response\AsyncContext;
use Symfony\Component\HttpClient\Response\AsyncResponse;
use Symfony\Contracts\HttpClient\ChunkInterface;
use Symfony\Contracts\HttpClient\Exception\TransportExceptionInterface;
use Symfony\Contracts\HttpClient\HttpClientInterface;
use Symfony\Contracts\HttpClient\ResponseInterface;

/** Records failures without changing response handling, retries, or request payloads. */
#[AsDecorator(decorates: 'http_client')]
final class OutboundErrorHttpClient implements HttpClientInterface
{
    use AsyncDecoratorTrait;

    public function __construct(#[AutowireDecorated] HttpClientInterface $client, private readonly LoggerInterface $logger)
    {
        $this->client = $client;
    }

    /** @param array<string, mixed> $options */
    public function request(string $method, string $url, array $options = []): ResponseInterface
    {
        $expected = $options['extra']['expected_http_statuses'] ?? [];
        $recorded = false;
        $record = function (string $kind, ?int $status, string $actualUrl) use ($method, &$recorded): void {
            if ($recorded) {
                return;
            }
            $recorded = true;
            $this->logger->error('outbound_http_failure', [
                'event' => 'outbound_http_failure',
                'integration' => parse_url(url: $actualUrl, component: PHP_URL_HOST) ?: 'unknown',
                'method' => strtoupper(string: $method),
                'failure_kind' => $kind,
                'status_code' => $status,
            ]);
        };

        try {
            return new AsyncResponse(client: $this->client, method: $method, url: $url, options: $options, passthru: static function (ChunkInterface $chunk, AsyncContext $context) use ($url, $expected, $record): \Generator {
                try {
                    if ($chunk->isTimeout()) {
                        $record('timeout', null, $url);
                    } elseif ($chunk->isFirst()) {
                        $status = $context->getStatusCode();
                        if ($status >= 400 && !in_array(needle: $status, haystack: $expected, strict: true)) {
                            $record('http_status', $status, (string) $context->getInfo(type: 'url'));
                        }
                    }
                } catch (TransportExceptionInterface $exception) {
                    $record(self::transportFailureKind(exception: $exception), null, $url);
                    throw $exception;
                }
                yield $chunk;
            });
        } catch (TransportExceptionInterface $exception) {
            $record(self::transportFailureKind(exception: $exception), null, $url);
            throw $exception;
        }
    }

    private static function transportFailureKind(TransportExceptionInterface $exception): string
    {
        return 1 === preg_match(pattern: '/timed out|timeout|max duration/i', subject: $exception->getMessage()) ? 'timeout' : 'transport';
    }
}
