<?php

declare(strict_types=1);

namespace App\Controller;

use App\Monitoring\HttpMetricsRegistry;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

final readonly class MetricsController
{
    public function __construct(
        private HttpMetricsRegistry $httpMetricsRegistry,
    ) {
    }

    #[Route('/metrics', name: 'metrics_prometheus', methods: ['GET'])]
    public function __invoke(): Response
    {
        return new Response(
            content: $this->httpMetricsRegistry->render(),
            status: Response::HTTP_OK,
            headers: ['Content-Type' => 'text/plain; version=0.0.4; charset=utf-8'],
        );
    }
}
