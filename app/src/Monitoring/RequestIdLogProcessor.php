<?php

declare(strict_types=1);

namespace App\Monitoring;

use Monolog\LogRecord;
use Symfony\Component\DependencyInjection\Attribute\AutoconfigureTag;

#[AutoconfigureTag('monolog.processor')]
final readonly class RequestIdLogProcessor
{
    public function __construct(
        private RequestIdContext $requestIdContext,
    ) {
    }

    public function __invoke(LogRecord $record): LogRecord
    {
        $requestId = $this->requestIdContext->getCurrentRequestId();
        if (null === $requestId || '' === $requestId) {
            return $record;
        }

        return $record->with(extra: array_merge($record->extra, [
            'request_id' => $requestId,
        ]));
    }
}
