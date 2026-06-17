<?php

declare(strict_types=1);

namespace App\Monitoring;

use Symfony\Contracts\Service\ResetInterface;

final class RequestIdContext implements ResetInterface
{
    private ?string $currentRequestId = null;

    public function assignNew(): string
    {
        $this->currentRequestId = bin2hex(random_bytes(16));

        return $this->currentRequestId;
    }

    public function getCurrentRequestId(): ?string
    {
        return $this->currentRequestId;
    }

    public function reset(): void
    {
        $this->currentRequestId = null;
    }
}
