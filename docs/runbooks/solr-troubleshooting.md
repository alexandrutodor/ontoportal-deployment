# Runbook: Solr search issues

1. Check Solr pods:

   ```bash
   kubectl -n <namespace> get pods -l app.kubernetes.io/component=solr
   ```

2. Port-forward Solr:

   ```bash
   kubectl -n <namespace> port-forward svc/<release>-solr-term 18983:8983
   curl http://127.0.0.1:18983/solr/admin/cores
   ```

3. Confirm API environment points at the right cores:

   ```bash
   kubectl -n <namespace> exec deploy/<release>-api -- env | grep SOLR
   ```

4. Common causes:

   - wrong term/property core names;
   - missing upstream OntoPortal Solr configsets;
   - PVC data from another Solr version;
   - disk pressure on the k3s node.

5. Recovery:

   - restore a known-good Solr PVC snapshot;
   - rebuild search indexes through the OntoPortal maintenance process;
   - for test installs only, delete Solr PVCs and let them recreate.
