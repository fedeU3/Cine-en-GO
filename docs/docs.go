// Package docs sirve la especificación OpenAPI y la interfaz de Swagger UI.
package docs

import (
	_ "embed"
	"net/http"
)

//go:embed openapi.yaml
var spec []byte

const swaggerUI = `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <title>Cine API - Swagger</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css">
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script>
    window.ui = SwaggerUIBundle({ url: "/swagger/openapi.yaml", dom_id: "#swagger-ui" });
  </script>
</body>
</html>`

// Register expone /swagger/ (Swagger UI) y /swagger/openapi.yaml (especificación).
func Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /swagger/openapi.yaml", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/yaml")
		w.Write(spec)
	})
	mux.HandleFunc("GET /swagger/{$}", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Write([]byte(swaggerUI))
	})
	mux.Handle("GET /swagger", http.RedirectHandler("/swagger/", http.StatusMovedPermanently))
}
