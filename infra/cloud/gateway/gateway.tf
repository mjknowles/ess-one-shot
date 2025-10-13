########################
# Gateway Configuration
########################

resource "time_sleep" "wait_for_gateway_api" {
  depends_on = [data.terraform_remote_state.base]
  create_duration = "90s"
}

# Gateway manifest (Google-managed global L7 LB)
resource "kubernetes_manifest" "gateway" {
  manifest = yamldecode(<<-YAML
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ${local.gateway_name}
  namespace: ${local.ess_namespace}
  annotations:
    # Attach Certificate Map managed in Certificate Manager
    networking.gke.io/certmap: ${local.certificate_map}
spec:
  gatewayClassName: gke-l7-global-external-managed
  addresses:
  - type: IPAddress
    value: ${local.gateway_ip}

  listeners:
  - name: ${local.gateway_listener_wildcard}
    hostname: "*.${local.base_domain}"
    port: 443
    protocol: HTTPS
    allowedRoutes:
      namespaces:
        from: Same
  - name: ${local.gateway_listener_root}
    hostname: ${local.base_domain}
    port: 443
    protocol: HTTPS
    allowedRoutes:
      namespaces:
        from: Same
YAML
  )

  depends_on = [
    time_sleep.wait_for_gateway_api
  ]
}

########################
# HTTPRoutes
########################

# Element Admin
resource "kubernetes_manifest" "route_element_admin" {
  manifest = yamldecode(<<-YAML
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ess-element-admin
  namespace: ${local.ess_namespace}
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

# Element Web
resource "kubernetes_manifest" "route_element_web" {
  manifest = yamldecode(<<-YAML
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ess-element-web
  namespace: ${local.ess_namespace}
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

# Matrix Auth
resource "kubernetes_manifest" "route_matrix_auth" {
  manifest = yamldecode(<<-YAML
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ess-matrix-authentication-service
  namespace: ${local.ess_namespace}
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

# Matrix RTC
resource "kubernetes_manifest" "route_matrix_rtc" {
  manifest = yamldecode(<<-YAML
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ess-matrix-rtc
  namespace: ${local.ess_namespace}
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

# Matrix Core
resource "kubernetes_manifest" "route_matrix" {
  manifest = yamldecode(<<-YAML
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ess-matrix
  namespace: ${local.ess_namespace}
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
        value: /_matrix/client
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

# Well-Known
resource "kubernetes_manifest" "route_well_known" {
  manifest = yamldecode(<<-YAML
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ess-well-known
  namespace: ${local.ess_namespace}
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
