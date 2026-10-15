<?php

declare(strict_types=1);

namespace App\Tests\Feature;

use App\Shared\Http\OutboundErrorHttpClient;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;
use Psr\Log\LoggerInterface;
use Symfony\Component\HttpClient\Exception\TransportException;
use Symfony\Component\HttpClient\MockHttpClient;
use Symfony\Component\HttpClient\Response\MockResponse;
use Symfony\Contracts\HttpClient\Exception\TransportExceptionInterface;

final class OutboundErrorHttpClientTest extends TestCase
{
    /** @return iterable<string, array{string, string}> */
    public static function failures(): iterable
    {
        yield 'idle timeout' => ['Idle timeout reached for https://provider.test/private?token=secret', 'timeout'];
        yield 'maximum duration' => ['Max duration was reached for https://provider.test/private?token=secret', 'timeout'];
        yield 'curl timeout' => ['Operation timed out after 180000 milliseconds', 'timeout'];
        yield 'connection reset' => ['Recv failure: Connection reset by peer', 'transport'];
    }

    #[DataProvider('failures')]
    public function testLazyTransportFailureIsClassifiedOnceWithoutLeakingPayload(string $message, string $kind): void
    {
        $logger = $this->createMock(LoggerInterface::class);
        $logger->expects($this->once())->method('error')->with('outbound_http_failure', [
            'event' => 'outbound_http_failure', 'integration' => 'provider.test', 'method' => 'POST', 'failure_kind' => $kind, 'status_code' => null,
        ]);
        $client = new OutboundErrorHttpClient(client: new MockHttpClient(responseFactory: new MockResponse(body: [new TransportException(message: $message)])), logger: $logger);
        $response = $client->request(method: 'POST', url: 'https://provider.test/private?token=secret');

        $this->expectException(TransportExceptionInterface::class);
        $response->getContent();
    }
}
