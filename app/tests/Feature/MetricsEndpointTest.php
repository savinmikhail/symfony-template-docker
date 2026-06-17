<?php

declare(strict_types=1);

namespace App\Tests\Feature;

use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;
use Symfony\Component\HttpFoundation\Response;

final class MetricsEndpointTest extends WebTestCase
{
    public function testMetricsEndpointExposesHttpCountersAndHistograms(): void
    {
        $client = self::createClient();

        $client->request(method: 'GET', uri: '/__metrics_test_missing');
        self::assertResponseStatusCodeSame(Response::HTTP_NOT_FOUND);

        $client->request(method: 'GET', uri: '/metrics');
        self::assertResponseIsSuccessful();

        $body = (string) $client->getResponse()->getContent();
        self::assertStringContainsString('# TYPE app_http_requests_total counter', $body);
        self::assertStringContainsString('# TYPE app_http_request_duration_seconds histogram', $body);
        self::assertMatchesRegularExpression(
            '/app_http_requests_total\{route="unmatched",method="GET",status_class="4xx"\} \d+/',
            $body,
        );
        self::assertMatchesRegularExpression(
            '/app_http_request_duration_seconds_bucket\{route="unmatched",method="GET",status_class="4xx",le="\\+Inf"\} \d+/',
            $body,
        );
    }
}
