locals {
  gateway_certificate_ref = google_certificate_manager_certificate_map.gateway.id
}

resource "kubernetes_manifest" "gateway" {
  manifest = yamldecode(<<-YAML
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ${local.gateway_name}
  namespace: ${kubernetes_namespace.ess.metadata[0].name}
spec:
  gatewayClassName: gke-l7-global-external-managed
  addresses:
  - type: IPAddress
    value: ${google_compute_global_address.gateway.address}
  listeners:
  - name: ${local.gateway_listener_wildcard}
    hostname: "*.${local.base_domain}"
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - group: networking.gke.io
        kind: CertificateMap
        name: ${local.gateway_certificate_ref}
    allowedRoutes:
      namespaces:
        from: Same
  - name: ${local.gateway_listener_root}
    hostname: ${local.base_domain}
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - group: networking.gke.io
        kind: CertificateMap
        name: ${local.gateway_certificate_ref}
    allowedRoutes:
      namespaces:
        from: Same
YAML
  )

  depends_on = [
    google_project_service.networkservices,
    google_certificate_manager_certificate_map_entry.base,
    google_certificate_manager_certificate_map_entry.wildcard
  ]
}

resource "kubernetes_manifest" "route_element_admin" {
  manifest = yamldecode(<<-YAML
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ess-element-admin
  namespace: ${kubernetes_namespace.ess.metadata[0].name}
spec:
  parentRefs:
  - name: ${local.gateway_name}
    sectionName: ${local.gateway_listener_wildcard}
  hostnames:
  - ${local.hostnames.admin}
  rules:
  - backendRefs:
    - name: ess-element-admin
      port: 8080
YAML
  )

  depends_on = [kubernetes_manifest.gateway]
}

resource "kubernetes_manifest" "route_element_web" {
  manifest = yamldecode(<<-YAML
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ess-element-web
  namespace: ${kubernetes_namespace.ess.metadata[0].name}
spec:
  parentRefs:
  - name: ${local.gateway_name}
    sectionName: ${local.gateway_listener_wildcard}
  hostnames:
  - ${local.hostnames.chat}
  rules:
  - backendRefs:
    - name: ess-element-web
      port: 80
YAML
  )

  depends_on = [kubernetes_manifest.gateway]
}

resource "kubernetes_manifest" "route_matrix_auth" {
  manifest = yamldecode(<<-YAML
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ess-matrix-authentication-service
  namespace: ${kubernetes_namespace.ess.metadata[0].name}
spec:
  parentRefs:
  - name: ${local.gateway_name}
    sectionName: ${local.gateway_listener_wildcard}
  hostnames:
  - ${local.hostnames.account}
  rules:
  - backendRefs:
    - name: ess-matrix-authentication-service
      port: 8080
YAML
  )

  depends_on = [kubernetes_manifest.gateway]
}

resource "kubernetes_manifest" "route_matrix_rtc" {
  manifest = yamldecode(<<-YAML
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ess-matrix-rtc
  namespace: ${kubernetes_namespace.ess.metadata[0].name}
spec:
  parentRefs:
  - name: ${local.gateway_name}
    sectionName: ${local.gateway_listener_wildcard}
  hostnames:
  - ${local.hostnames.rtc}
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /sfu/get
    backendRefs:
    - name: ess-matrix-rtc-authorisation-service
      port: 8080
  - backendRefs:
    - name: ess-matrix-rtc-sfu
      port: 7880
YAML
  )

  depends_on = [kubernetes_manifest.gateway]
}

resource "kubernetes_manifest" "route_matrix" {
  manifest = yamldecode(<<-YAML
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ess-matrix
  namespace: ${kubernetes_namespace.ess.metadata[0].name}
spec:
  parentRefs:
  - name: ${local.gateway_name}
    sectionName: ${local.gateway_listener_wildcard}
  hostnames:
  - ${local.hostnames.matrix}
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /_matrix/client/api/v1/login
    - path:
        type: PathPrefix
        value: /_matrix/client/api/v1/refresh
    - path:
        type: PathPrefix
        value: /_matrix/client/api/v1/logout
    - path:
        type: PathPrefix
        value: /_matrix/client/r0/login
    - path:
        type: PathPrefix
        value: /_matrix/client/r0/refresh
    - path:
        type: PathPrefix
        value: /_matrix/client/r0/logout
    - path:
        type: PathPrefix
        value: /_matrix/client/v3/login
    - path:
        type: PathPrefix
        value: /_matrix/client/v3/refresh
    - path:
        type: PathPrefix
        value: /_matrix/client/v3/logout
    - path:
        type: PathPrefix
        value: /_matrix/client/unstable/login
    - path:
        type: PathPrefix
        value: /_matrix/client/unstable/refresh
    - path:
        type: PathPrefix
        value: /_matrix/client/unstable/logout
    backendRefs:
    - name: ess-matrix-authentication-service
      port: 8080
  - matches:
    - path:
        type: PathPrefix
        value: /_matrix
    - path:
        type: PathPrefix
        value: /_synapse
    backendRefs:
    - name: ess-synapse
      port: 8008
YAML
  )

  depends_on = [kubernetes_manifest.gateway]
}

resource "kubernetes_manifest" "route_well_known" {
  manifest = yamldecode(<<-YAML
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ess-well-known
  namespace: ${kubernetes_namespace.ess.metadata[0].name}
spec:
  parentRefs:
  - name: ${local.gateway_name}
    sectionName: ${local.gateway_listener_root}
  hostnames:
  - ${local.base_domain}
  rules:
  - backendRefs:
    - name: ess-well-known
      port: 8010
YAML
  )

  depends_on = [kubernetes_manifest.gateway]
}
