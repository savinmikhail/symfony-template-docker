<?php

declare(strict_types=1);

require $argv[1];
require $argv[2];

use App\Shared\Http\OutboundErrorHttpClient;
use Psr\Log\AbstractLogger;
use Symfony\Component\HttpClient\MockHttpClient;
use Symfony\Component\HttpClient\Response\MockResponse;
use Symfony\Component\HttpClient\Exception\TransportException;
use Symfony\Contracts\HttpClient\Exception\TransportExceptionInterface;

$logger = new class extends AbstractLogger {
    public array $records = [];
    public function log($level, string|Stringable $message, array $context = []): void
    {
        $this->records[] = [$level, $message, $context];
    }
};
$check = static function (bool $ok, string $message): void {
    if (!$ok) {
        throw new RuntimeException($message);
    }
};
foreach ([200, 400, 401, 402, 403, 404, 429, 500, 503] as $status) {
    $logger->records = [];
    $client = new OutboundErrorHttpClient(new MockHttpClient(new MockResponse('secret-body', ['http_code' => $status])), $logger);
    $response = $client->request('POST', 'https://user:secret@api.example.com/botSECRET/send?token=SECRET', ['json' => ['password' => 'SECRET']]);
    $check($response->getStatusCode() === $status, 'status changed');
    $check($response->getContent(false) === 'secret-body', 'body changed');
    $check(count($logger->records) === ($status >= 400 ? 1 : 0), 'wrong number of records for '.$status);
    $check(!str_contains(json_encode($logger->records, JSON_THROW_ON_ERROR), 'SECRET'), 'credential leaked');
}
$logger->records = [];
$client = new OutboundErrorHttpClient(new MockHttpClient(new MockResponse('', ['http_code' => 404])), $logger);
$client->request('GET', 'https://api.example.com/expected', ['extra' => ['expected_http_statuses' => [404]]])->getContent(false);
$check($logger->records === [], 'expected status should not alert');
$logger->records = [];
$body = static function (): Generator {
    throw new TransportException('SECRET transport details');
    yield '';
};
$client = new OutboundErrorHttpClient(new MockHttpClient(new MockResponse($body())), $logger);
try {
    $client->request('GET', 'https://api.example.com/?secret=SECRET')->getContent(false);
    throw new RuntimeException('transport exception swallowed');
} catch (TransportExceptionInterface) {
    $check(count($logger->records) === 1, 'transport failure not recorded exactly once');
    $check(!str_contains(json_encode($logger->records, JSON_THROW_ON_ERROR), 'SECRET'), 'transport details leaked');
}
echo "PASS outbound HTTP: statuses, redaction, expected status, lazy transport failure\n";
