public without sharing class ProformaInvoiceTriggerHandler {

    private static final String STATUS_SENT = 'Sent';

    /*
     * =========================================================
     * AFTER UPDATE - EMAIL DISPATCH
     * =========================================================
     *
     * Centralizes the Proforma_Invoice__c after-update side effects
     * (file sharing, client approval request email, client decision
     * notifications, manager decision notifications) so they fire
     * off the record's own state transitions, regardless of which
     * Apex class, Flow, or integration performed the save.
     * ProformaInvoiceController and ProformaManagerController only
     * persist data - all after-update email dispatch lives here.
     */
    public static void handleAfterUpdate(List<Proforma_Invoice__c> newList, Map<Id, Proforma_Invoice__c> oldMap) {
        Map<Id, Id> invoiceToOppMap = new Map<Id, Id>();

        for (Proforma_Invoice__c newInv : newList) {
            Proforma_Invoice__c oldInv = oldMap.get(newInv.Id);

            collectApprovedInvoiceForFileSharing(newInv, oldInv, invoiceToOppMap);
            fireClientApprovalRequestEmail(newInv, oldInv);
            fireClientDecisionNotifications(newInv, oldInv);
            fireManagerDecisionNotifications(newInv, oldInv);
        }

        if (!invoiceToOppMap.isEmpty()) {
            FileVisibilityHandler.shareFilesWithOpportunity(invoiceToOppMap);
        }
    }

    private static void collectApprovedInvoiceForFileSharing(
        Proforma_Invoice__c newInv,
        Proforma_Invoice__c oldInv,
        Map<Id, Id> invoiceToOppMap
    ) {
        if (newInv.Manager_Approval__c && !oldInv.Manager_Approval__c && newInv.Opportunity__c != null) {
            invoiceToOppMap.put(newInv.Id, newInv.Opportunity__c);
        }
    }

    /**
     * Fires when a Proforma_Invoice__c is first submitted for client approval,
     * i.e. Status__c transitions into 'Sent'.
     */
    private static void fireClientApprovalRequestEmail(Proforma_Invoice__c newInv, Proforma_Invoice__c oldInv) {
        Boolean justSent = newInv.Status__c == STATUS_SENT && oldInv.Status__c != STATUS_SENT;
        if (!justSent) {
            return;
        }

        try {
            ProformaInvoiceController.sendClientApprovalRequestEmail(newInv.Id);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Proforma client approval request email failed: ' + ex.getMessage());
        }
    }

    /**
     * Fires when the client makes a decision, i.e. Status__c moves away from 'Sent'
     * to something else (Approved / Changes Requested).
     */
    private static void fireClientDecisionNotifications(Proforma_Invoice__c newInv, Proforma_Invoice__c oldInv) {
        Boolean clientDecided = newInv.Status__c != oldInv.Status__c && newInv.Status__c != STATUS_SENT;
        if (!clientDecided) {
            return;
        }

        try {
            ProformaInvoiceController.sendClientDecisionNotifications(newInv.Id, newInv.Status__c, newInv.Client_Comments__c);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Proforma client decision notification failed: ' + ex.getMessage());
        }
    }

    /**
     * Fires when the manager records a decision. Manager_Approval__c alone isn't a reliable
     * signal (a Reject leaves it false -> false when the invoice was never approved), so this
     * also checks Manager_Comments__c, which a decision always sets.
     */
    private static void fireManagerDecisionNotifications(Proforma_Invoice__c newInv, Proforma_Invoice__c oldInv) {
        Boolean managerDecided = String.isNotBlank(newInv.Manager_Comments__c)
            && (newInv.Manager_Approval__c != oldInv.Manager_Approval__c || newInv.Manager_Comments__c != oldInv.Manager_Comments__c);
        if (!managerDecided) {
            return;
        }

        try {
            String action = newInv.Manager_Approval__c ? 'Approve' : 'Reject';
            ProformaManagerController.sendManagerDecisionNotifications(newInv.Id, action, newInv.Manager_Comments__c);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Proforma manager decision notification failed: ' + ex.getMessage());
        }
    }

    /*
     * =========================================================
     * FIREBASE CONFIGURATION
     * =========================================================
     *
     * Change FIREBASE_PROJECT_ID if your actual
     * Firebase project ID is different.
     *
     * Named Credential:
     * Firebase_FCM
     *
     * Base URL:
     * https://fcm.googleapis.com
     */
    private static final String FIREBASE_PROJECT_ID =
        'areliaspace-e5f22';

    private static final String FCM_NAMED_CREDENTIAL =
        'Firebase_FCM';


    /*
     * =========================================================
     * BEFORE INSERT
     * =========================================================
     *
     * Automatically generate Secure_Token__c
     * if it is empty.
     */
    public static void beforeInsert(
        List<Proforma_Invoice__c> newInvoices
    ) {

        if (newInvoices == null || newInvoices.isEmpty()) {
            return;
        }

        for (Proforma_Invoice__c invoice : newInvoices) {

            if (String.isBlank(invoice.Secure_Token__c)) {

                invoice.Secure_Token__c =
                    EncodingUtil.convertToHex(
                        Crypto.generateAesKey(256)
                    );
            }
        }
    }


    /*
     * =========================================================
     * AFTER INSERT
     * =========================================================
     *
     * Trigger should only enqueue the notification processing.
     *
     * Firebase callout cannot be executed directly
     * from the trigger transaction.
     */
    public static void afterInsert(
        Set<Id> invoiceIds
    ) {

        if (invoiceIds == null || invoiceIds.isEmpty()) {
            return;
        }

        System.enqueueJob(
            new ProformaPushNotificationJob(
                new List<Id>(invoiceIds)
            )
        );
    }


    /*
     * =========================================================
     * QUEUEABLE NOTIFICATION JOB
     * =========================================================
     */
    public class ProformaPushNotificationJob
        implements Queueable, Database.AllowsCallouts {

        private List<Id> invoiceIds;


        public ProformaPushNotificationJob(
            List<Id> invoiceIds
        ) {
            this.invoiceIds = invoiceIds;
        }


        public void execute(
            QueueableContext context
        ) {

            if (invoiceIds == null || invoiceIds.isEmpty()) {
                return;
            }


            /*
             * =================================================
             * STEP 1:
             * Get newly created Proforma Invoice records
             * =================================================
             */
            List<Proforma_Invoice__c> invoices = [
                SELECT
                    Id,
                    Name,
                    Opportunity__c,
                    Status__c,
                    Secure_Token__c
                FROM Proforma_Invoice__c
                WHERE Id IN :invoiceIds
                AND Opportunity__c != null
            ];


            if (invoices.isEmpty()) {
                return;
            }


            /*
             * =================================================
             * STEP 2:
             * Collect Opportunity IDs
             * =================================================
             */
            Set<Id> opportunityIds = new Set<Id>();

            for (Proforma_Invoice__c invoice : invoices) {

                if (invoice.Opportunity__c != null) {
                    opportunityIds.add(
                        invoice.Opportunity__c
                    );
                }
            }


            if (opportunityIds.isEmpty()) {
                return;
            }


            /*
             * =================================================
             * STEP 3:
             * Find the converted Lead related to each Opportunity
             *
             * Example:
             *
             * Bhavana Lead
             *      ↓ Lead Conversion
             * Bhavana Opportunity
             *
             * ConvertedOpportunityId stores that relationship.
             * =================================================
             */
            Map<Id, Id> opportunityToLeadMap =
                new Map<Id, Id>();

            Map<Id, Id> opportunityToContactMap =
                new Map<Id, Id>();


            for (Lead prospectLead : [
                SELECT
                    Id,
                    ConvertedOpportunityId,
                    ConvertedContactId
                FROM Lead
                WHERE IsConverted = true
                AND ConvertedOpportunityId IN :opportunityIds
            ]) {

                if (
                    prospectLead.ConvertedOpportunityId != null &&
                    !opportunityToLeadMap.containsKey(
                        prospectLead.ConvertedOpportunityId
                    )
                ) {

                    opportunityToLeadMap.put(
                        prospectLead.ConvertedOpportunityId,
                        prospectLead.Id
                    );

                    if (prospectLead.ConvertedContactId != null) {
                        opportunityToContactMap.put(
                            prospectLead.ConvertedOpportunityId,
                            prospectLead.ConvertedContactId
                        );
                    }
                }
            }


            if (opportunityToLeadMap.isEmpty()) {
                return;
            }


            /*
             * =================================================
             * STEP 4:
             * Collect only those customer Contact IDs
             * =================================================
             */
            Set<Id> contactIds =
                new Set<Id>();


            contactIds.addAll(
                opportunityToContactMap.values()
            );


            /*
             * =================================================
             * STEP 5:
             * Find active mobile devices belonging ONLY
             * to those Leads.
             *
             * Mobile_Device_Token__c is keyed by Contact__c,
             * so we look up tokens via the converted Contact.
             *
             * NOT Lead__c.
             *
             * FCM_Token__c is Long Text Area,
             * so we don't filter blank values in SOQL.
             * =================================================
             */
            Map<Id, Set<String>> contactToTokensMap =
                new Map<Id, Set<String>>();


            for (Mobile_Device_Token__c device : [
                SELECT
                    Id,
                    Contact__c,
                    FCM_Token__c,
                    Active__c
                FROM Mobile_Device_Token__c
                WHERE Contact__c IN :contactIds
                AND Active__c = true
            ]) {

                /*
                 * Skip invalid device records.
                 */
                if (
                    device.Contact__c == null ||
                    String.isBlank(device.FCM_Token__c)
                ) {
                    continue;
                }


                /*
                 * Create token set for this Contact.
                 */
                if (
                    !contactToTokensMap.containsKey(
                        device.Contact__c
                    )
                ) {

                    contactToTokensMap.put(
                        device.Contact__c,
                        new Set<String>()
                    );
                }


                /*
                 * Add device token.
                 *
                 * Set prevents duplicate notification
                 * if same FCM token exists twice.
                 */
                contactToTokensMap
                    .get(device.Contact__c)
                    .add(
                        device.FCM_Token__c.trim()
                    );
            }


            if (contactToTokensMap.isEmpty()) {
                return;
            }


            /*
             * =================================================
             * STEP 6:
             * Send notification only to the customer
             * related to that Proforma Invoice.
             * =================================================
             */
            for (Proforma_Invoice__c invoice : invoices) {

                /*
                 * Get Lead related to invoice Opportunity.
                 */
                Id prospectLeadId =
                    opportunityToLeadMap.get(
                        invoice.Opportunity__c
                    );

                Id customerContactId =
                    opportunityToContactMap.get(
                        invoice.Opportunity__c
                    );


                if (prospectLeadId == null || customerContactId == null) {
                    continue;
                }


                /*
                 * Get ONLY this Contact's tokens.
                 */
                Set<String> customerTokens =
                    contactToTokensMap.get(
                        customerContactId
                    );


                if (
                    customerTokens == null ||
                    customerTokens.isEmpty()
                ) {
                    continue;
                }


                /*
                 * One prospect may login on multiple devices.
                 * Send to all active devices belonging
                 * to that prospect only.
                 */
                for (String fcmToken : customerTokens) {

                    sendFirebaseNotification(
                        fcmToken,
                        prospectLeadId,
                        invoice
                    );
                }
            }
        }
    }


    /*
     * =========================================================
     * SEND FIREBASE PUSH NOTIFICATION
     * =========================================================
     */
    private static void sendFirebaseNotification(
        String fcmToken,
        Id prospectLeadId,
        Proforma_Invoice__c invoice
    ) {

        if (
            String.isBlank(fcmToken) ||
            prospectLeadId == null ||
            invoice == null
        ) {
            return;
        }


        /*
         * =====================================================
         * Notification displayed on mobile
         * =====================================================
         */
        Map<String, Object> notification =
            new Map<String, Object>{

                'title' =>
                    'Proforma Invoice Ready',

                'body' =>
                    'Your Proforma Invoice ' +
                    invoice.Name +
                    ' is ready. Please review and respond.'
            };


        /*
         * =====================================================
         * Flutter receives this data.
         *
         * When customer clicks notification:
         *
         * actionType = OPEN_PROFORMA_INVOICE
         *
         * Flutter should navigate to Proforma screen.
         * =====================================================
         */
        Map<String, String> data =
            new Map<String, String>{

                'notificationType' =>
                    'PROFORMA_INVOICE',

                'actionType' =>
                    'OPEN_PROFORMA_INVOICE',

                'route' =>
                    'prospect_proforma_invoice',

                'leadId' =>
                    String.valueOf(
                        prospectLeadId
                    ),

                'opportunityId' =>
                    String.valueOf(
                        invoice.Opportunity__c
                    ),

                'invoiceId' =>
                    String.valueOf(
                        invoice.Id
                    ),

                'secureToken' =>
                    String.valueOf(
                        invoice.Secure_Token__c
                    )
            };


        /*
         * =====================================================
         * Android configuration
         * =====================================================
         */
        Map<String, Object> androidNotification =
            new Map<String, Object>{

                'channel_id' =>
                    'high_importance_channel',

                'sound' =>
                    'default'
            };


        Map<String, Object> android =
            new Map<String, Object>{

                'priority' =>
                    'high',

                'notification' =>
                    androidNotification
            };


        /*
         * =====================================================
         * FCM Message
         * =====================================================
         */
        Map<String, Object> message =
            new Map<String, Object>{

                'token' =>
                    fcmToken,

                'notification' =>
                    notification,

                'data' =>
                    data,

                'android' =>
                    android
            };


        Map<String, Object> payload =
            new Map<String, Object>{

                'message' =>
                    message
            };


        /*
         * =====================================================
         * Firebase HTTP Callout
         * =====================================================
         */
        HttpRequest request =
            new HttpRequest();


        request.setEndpoint(
            'callout:' +
            FCM_NAMED_CREDENTIAL +
            '/v1/projects/' +
            FIREBASE_PROJECT_ID +
            '/messages:send'
        );


        request.setMethod(
            'POST'
        );


        request.setHeader(
            'Content-Type',
            'application/json'
        );


        request.setTimeout(
            20000
        );


        request.setBody(
            JSON.serialize(payload)
        );


        try {

            Http http =
                new Http();


            HttpResponse response =
                http.send(request);


            /*
             * Successful Firebase response:
             * normally HTTP 200.
             */
            if (
                response.getStatusCode() >= 200 &&
                response.getStatusCode() < 300
            ) {

                System.debug(
                    LoggingLevel.INFO,
                    'Proforma push sent successfully.' +
                    ' Invoice: ' +
                    invoice.Id +
                    ' Lead: ' +
                    prospectLeadId
                );

            } else {

                System.debug(
                    LoggingLevel.ERROR,
                    'Proforma push failed.' +
                    ' Invoice: ' +
                    invoice.Id +
                    ' Lead: ' +
                    prospectLeadId +
                    ' Status: ' +
                    response.getStatusCode() +
                    ' Response: ' +
                    response.getBody()
                );
            }

        } catch (Exception e) {

            System.debug(
                LoggingLevel.ERROR,
                'Firebase notification exception.' +
                ' Invoice: ' +
                invoice.Id +
                ' Lead: ' +
                prospectLeadId +
                ' Error: ' +
                e.getMessage()
            );
        }
    }
}