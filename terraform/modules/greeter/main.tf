resource "helm_release" "greeter" {
  name             = var.release_name
  namespace        = var.namespace
  create_namespace = true
  chart            = "${path.module}/../../../charts/greeter"

  set = [
    {
      name  = "deployment.greetingName"
      value = var.greeting_name
    },
    {
      name  = "deployment.replicaCount"
      value = tostring(var.replica_count)
    },
    {
      name  = "service.nodePort"
      value = tostring(var.node_port)
    }
  ]
}
