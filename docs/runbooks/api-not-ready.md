# Runbook: API pod is not ready

1. Check pod status:

   ```bash
   kubectl -n <namespace> get pods -l app.kubernetes.io/component=api
   kubectl -n <namespace> describe pod <api-pod>
   ```

2. Check dependencies:

   ```bash
   kubectl -n <namespace> get svc,pods | grep -E 'redis|solr|virtuoso|store|mgrep'
   ```

3. Check logs:

   ```bash
   kubectl -n <namespace> logs deploy/<release>-api --tail=200
   ```

4. Common causes:

   - Solr cores not initialized or too slow to start.
   - RDF store not reachable.
   - missing API key secret.
   - bundle install failure due to image/source mismatch.
   - local-path PVC scheduled on a different node from the workload.

5. Recovery:

   - restart the failing dependency;
   - check PVC binding and node scheduling;
   - rollback the Helm release if the failure started after an upgrade.
