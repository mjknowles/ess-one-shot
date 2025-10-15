resource "kubernetes_manifest" "healthcheckpolicy_haproxy" {
  manifest = yamldecode(<<-YAML
apiVersion: networking.gke.io/v1
kind: HealthCheckPolicy
metadata:
  name: ess-haproxy-hc
  namespace: ${local.ess_namespace}
spec:
  default:
    checkIntervalSec: 10
    timeoutSec: 5
    healthyThreshold: 1
    unhealthyThreshold: 3
    config:
      type: HTTP
      httpHealthCheck:
        port: 8405
        requestPath: /haproxy_test
  targetRef:
    group: ""
    kind: Service
    name: ess-haproxy
YAML
  )

  depends_on = [kubernetes_manifest.gateway]
}

resource "kubernetes_manifest" "healthcheckpolicy_matrix_rtc_auth" {
  manifest = yamldecode(<<-YAML
apiVersion: networking.gke.io/v1
kind: HealthCheckPolicy
metadata:
  name: ess-matrix-rtc-authorisation-service-hc
  namespace: ${local.ess_namespace}
spec:
  default:
    checkIntervalSec: 10
    timeoutSec: 1
    healthyThreshold: 1
    unhealthyThreshold: 3
    config:
      type: HTTP
      httpHealthCheck:
        port: 8080
        requestPath: /healthz
  targetRef:
    group: ""
    kind: Service
    name: ess-matrix-rtc-authorisation-service
YAML
  )

  depends_on = [kubernetes_manifest.gateway]
}
