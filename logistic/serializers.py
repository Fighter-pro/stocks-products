from django.db import transaction
from rest_framework import serializers

from logistic.models import Product, Stock, StockProduct


class ProductSerializer(serializers.ModelSerializer):
    class Meta:
        model = Product
        fields = ['id', 'title', 'description']


class ProductPositionSerializer(serializers.ModelSerializer):
    class Meta:
        model = StockProduct
        fields = ['product', 'quantity', 'price']


class StockSerializer(serializers.ModelSerializer):
    positions = ProductPositionSerializer(many=True)

    class Meta:
        model = Stock
        fields = ['id', 'address', 'positions']

    @transaction.atomic
    def create(self, validated_data):
        # достаем связанные данные для других таблиц
        positions = validated_data.pop('positions')

        # создаем склад по его параметрам
        stock = super().create(validated_data)

        # заполняем связанную таблицу StockProduct
        StockProduct.objects.bulk_create(
            StockProduct(stock=stock, **position) for position in positions
        )
        return stock

    @transaction.atomic
    def update(self, instance, validated_data):
        # при PATCH позиции могут не передать
        positions = validated_data.pop('positions', None)

        # обновляем склад по его параметрам
        stock = super().update(instance, validated_data)

        # обновляем или добавляем позиции на складе
        for position in positions or []:
            StockProduct.objects.update_or_create(
                stock=stock,
                product=position['product'],
                defaults={'quantity': position['quantity'], 'price': position['price']},
            )
        return stock
