@RestResource(urlMapping='/whatsappWebhook/*')
global without sharing class WhatsAppWebhookRest {

    @HttpGet
    global static void verify() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String mode  = req.params.get('hub.mode');
        String token = req.params.get('hub.verify_token');
        String chall = req.params.get('hub.challenge');

        Boolean ok = 'subscribe'.equalsIgnoreCase(mode) && WhatsAppConfig.verifyToken() == token;
        res.statusCode   = ok ? 200 : 403;
        res.responseBody = Blob.valueOf(ok ? (chall == null ? '' : chall) : 'Forbidden');
    }

    @HttpPost
    global static void ingest() {
        RestResponse res = RestContext.response;
        try {
            String raw = (RestContext.request.requestBody == null) ? '' : String.valueOf(RestContext.request.requestBody.toString());
            if (String.isBlank(raw)) { res.statusCode = 200; return; }

            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(raw);
            List<Object> entry = (List<Object>) root.get('entry');
            if (entry == null) { res.statusCode = 200; return; }

            for (Object eObj : entry) {
                Map<String, Object> e = (Map<String, Object>) eObj;
                List<Object> changes = (List<Object>) e.get('changes');
                if (changes == null) continue;

                for (Object cObj : changes) {
                    Map<String, Object> c = (Map<String, Object>) cObj;
                    Map<String, Object> val = (Map<String, Object>) c.get('value');
                    if (val == null) continue;

                    List<Object> messages = (List<Object>) val.get('messages');
                    if (messages != null) for (Object mObj : messages) handleMessage((Map<String, Object>) mObj);

                    List<Object> statuses = (List<Object>) val.get('statuses');
                    if (statuses != null) for (Object sObj : statuses) handleStatus((Map<String, Object>) sObj);
                }
            }
            res.statusCode = 200;
        } catch (Exception ex) {
            System.debug('WA webhook error: ' + ex.getMessage());
            // Always ACK to avoid WA retries
            res.statusCode = 200;
        }
    }

    // ---------- helpers ----------

    // Build a human-friendly label from media block
    private static String mediaLabel(String kind, Map<String,Object> blk) {
        if (blk == null) return '[' + kind + ']';
        String caption  = (String) blk.get('caption');
        String filename = (String) blk.get('filename');
        if (!String.isBlank(caption))  return caption;
        if (!String.isBlank(filename)) return filename;
        return '[' + kind + ']';
    }

    // Map 'document' → 'application' to keep your UI logic happy
    private static String normalizeMediaType(String kind) {
        return 'document'.equalsIgnoreCase(kind) ? 'application' : kind;
    }

    private static void handleMessage(Map<String, Object> m) {
        System.debug(LoggingLevel.WARN, 'WA IN RAW: ' + JSON.serialize(m));

        String from1 = (String) m.get('from');   // wa_id
        String wamid = (String) m.get('id');
        String type  = (String) m.get('type');

        // 1) MEDIA-FIRST (show-name-only, no downloads, no meta calls)
        String[] kinds = new String[]{ 'image','document','video','audio','sticker' };

        // A) If a known media type is declared
        if (!String.isBlank(type)) {
            for (String k : kinds) {
                if (k.equalsIgnoreCase(type)) {
                    Object rawBlk = m.get(k);
                    Map<String,Object> blk = (rawBlk instanceof Map<String,Object>) ? (Map<String,Object>) rawBlk : null;
                    String label = mediaLabel(k, blk);
                    String mt = normalizeMediaType(k);

                    // Always append at least a text line
                    WhatsAppChatStore.append(from1, 'IN', label, wamid, 'delivered', mt, null, null);
                    return;
                }
            }
        }

        // B) If type is missing or unexpected, see if any media block exists anyway
        for (String k : kinds) {
            Object rawBlk = m.get(k);
            if (rawBlk instanceof Map<String,Object>) {
                Map<String,Object> blk = (Map<String,Object>) rawBlk;
                String label = mediaLabel(k, blk);
                String mt = normalizeMediaType(k);
                WhatsAppChatStore.append(from1, 'IN', label, wamid, 'delivered', mt, null, null);
                return;
            }
        }

        // 2) TEXT / INTERACTIVE
        String textBody = null;

        if ('text'.equalsIgnoreCase(type) && m.get('text') != null) {
            Map<String, Object> t = (Map<String, Object>) m.get('text');
            textBody = (String) t.get('body');

        } else if ('button'.equalsIgnoreCase(type) && m.get('button') != null) {
            Map<String, Object> b = (Map<String, Object>) m.get('button');
            textBody = 'BUTTON: ' + (String) b.get('text');

        } else if ('interactive'.equalsIgnoreCase(type) && m.get('interactive') != null) {
            Map<String, Object> inter = (Map<String, Object>) m.get('interactive');
            Map<String, Object> br = (Map<String, Object>) inter.get('button_reply');
            Map<String, Object> lr = (Map<String, Object>) inter.get('list_reply');
            if (br != null)      textBody = 'BUTTON: ' + (String) br.get('title') + ' (id=' + (String) br.get('id') + ')';
            else if (lr != null) textBody = 'LIST: ' + (String) lr.get('title') + ' (id=' + (String) lr.get('id') + ')';
        }

        if (textBody != null) {
            WhatsAppChatStore.append(from1, 'IN', textBody, wamid, 'delivered', null, null, null);
        } else {
            // Last resort: keep the payload so you can inspect it from UI if needed
            WhatsAppChatStore.append(from1, 'IN', '[UNHANDLED] ' + JSON.serialize(m), wamid, 'delivered', null, null, null);
        }
    }

    private static void handleStatus(Map<String, Object> s) {
        String status = (String) s.get('status');
        String id     = (String) s.get('id');
        String who    = (String) s.get('recipient_id');

        // 8 args: (e164, dir, text, messageId, status, mediaType, contentDocumentId, externalUrl)
        WhatsAppChatStore.append(
            who, 'IN',
            '[STATUS] id=' + id + ' status=' + status + ' to=' + who,
            id, status, null, null, null
        );
    }
}