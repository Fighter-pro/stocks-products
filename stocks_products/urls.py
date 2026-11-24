from django.contrib import admin
from django.urls import include, path
from django.views.generic import RedirectView

urlpatterns = [
    # корень сайта ведёт на API, чтобы по ссылке сразу открывался работающий интерфейс
    path('', RedirectView.as_view(url='/api/v1/', permanent=False)),
    path('admin/', admin.site.urls),
    path('api/v1/', include('logistic.urls')),
]
