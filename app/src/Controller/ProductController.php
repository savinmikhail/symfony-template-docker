<?php

declare(strict_types=1);

namespace App\Controller;

use App\Entity\Product;
use App\Repository\ProductRepository;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

#[Route('/products', name: 'product_')]
class ProductController extends AbstractController
{
    #[Route('', name: 'list', methods: ['GET'])]
    public function list(ProductRepository $repository): JsonResponse
    {
        $products = $repository->findBy([], ['id' => 'DESC'], 50);

        return $this->json(
            array_map(
                static fn (Product $product): array => [
                    'id' => $product->getId(),
                    'name' => $product->getName(),
                    'price' => $product->getPrice(),
                    'createdAt' => $product->getCreatedAt()->format(\DATE_ATOM),
                    'updatedAt' => $product->getUpdatedAt()?->format(\DATE_ATOM),
                ],
                $products,
            ),
        );
    }

    #[Route('', name: 'create', methods: ['POST'])]
    public function create(Request $request, EntityManagerInterface $em): JsonResponse
    {
        $data = json_decode((string) $request->getContent(), true, 512, JSON_THROW_ON_ERROR);

        if (!isset($data['name'], $data['price']) || !is_string($data['name']) || !is_numeric($data['price'])) {
            return $this->json(['error' => 'Invalid payload'], Response::HTTP_BAD_REQUEST);
        }

        $product = new Product($data['name'], (string) $data['price']);

        $em->persist($product);
        $em->flush();

        return $this->json(
            [
                'id' => $product->getId(),
                'name' => $product->getName(),
                'price' => $product->getPrice(),
                'createdAt' => $product->getCreatedAt()->format(\DATE_ATOM),
                'updatedAt' => $product->getUpdatedAt()?->format(\DATE_ATOM),
            ],
            Response::HTTP_CREATED,
        );
    }
}

