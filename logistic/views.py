from django.db.models import Q
from django_filters import rest_framework as filters
from rest_framework.filters import SearchFilter
from rest_framework.viewsets import ModelViewSet

from logistic.models import Product, Stock
from logistic.serializers import ProductSerializer, StockSerializer


class ProductViewSet(ModelViewSet):
    queryset = Product.objects.all().order_by('id')
    serializer_class = ProductSerializer
    # поиск по названию и описанию: ?search=помидор
    filter_backends = [SearchFilter]
    search_fields = ['title', 'description']


class StockFilter(filters.FilterSet):
    """?products=2 — склады с продуктом id=2; ?products=помид — по части названия или описания."""

    products = filters.CharFilter(method='filter_products', label='Продукт (id или часть названия)')

    class Meta:
        model = Stock
        fields = ['products']

    def filter_products(self, queryset, name, value):
        value = value.strip()
        if value.isdigit():
            return queryset.filter(products__id=int(value)).distinct()
        return queryset.filter(
            Q(products__title__icontains=value) | Q(products__description__icontains=value)
        ).distinct()


class StockViewSet(ModelViewSet):
    queryset = Stock.objects.prefetch_related('positions').order_by('id')
    serializer_class = StockSerializer
    filter_backends = [filters.DjangoFilterBackend, SearchFilter]
    filterset_class = StockFilter
    # дополнительно: ?search=помид ищет по продуктам на складе
    search_fields = ['products__title', 'products__description']
