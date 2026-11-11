@RestResource(urlMapping='/registration/lead/device-token')
global without sharing class ProspectDeviceTokenRestController {
    global class TokenRequest {
        public String action;
        public String leadId;
        public String deviceId;
        public String fcmToken;
        public String platform;
        public String appVersion;
    }

    @HttpPost
    global static void handleDeviceToken() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');
        Savepoint checkpoint = Database.setSavepoint();
        try {
            if (RestContext.request == null || RestContext.request.requestBody == null) {
                reply(400, false, 'Request body is required.');
                return;
            }
            TokenRequest input = (TokenRequest) JSON.deserialize(
                RestContext.request.requestBody.toString(), TokenRequest.class);
            if (input == null) {
                reply(400, false, 'Request body is required.');
                return;
            }
            String action = String.isBlank(input.action) ? 'save' : input.action.trim().toLowerCase();
            if (action != 'save' && action != 'deactivate') {
                reply(400, false, 'Invalid device token action.');
                return;
            }
            input.deviceId = String.isBlank(input.deviceId) ? null : input.deviceId.trim();
            input.fcmToken = String.isBlank(input.fcmToken) ? null : input.fcmToken.trim();
            if (action == 'deactivate') {
                if (input.deviceId == null && input.fcmToken == null) {
                    reply(400, false, 'Device ID or FCM token is required.');
                    return;
                }
                // Logout affects this installation, including all its project associations.
                List<Prospect_Device_Token__c> prospects = new List<Prospect_Device_Token__c>();
                for (Prospect_Device_Token__c token : [
                    SELECT Id, Device_Id__c, FCM_Token__c, Active__c
                    FROM Prospect_Device_Token__c WHERE Active__c = true
                ]) {
                    if ((input.deviceId != null && token.Device_Id__c == input.deviceId) ||
                        (input.fcmToken != null && input.fcmToken.equals(token.FCM_Token__c))) {
                        token.Active__c = false;
                        prospects.add(token);
                    }
                }
                List<Mobile_Device_Token__c> contacts = new List<Mobile_Device_Token__c>();
                for (Mobile_Device_Token__c token : [
                    SELECT Id, Device_Id__c, FCM_Token__c, Active__c
                    FROM Mobile_Device_Token__c WHERE Active__c = true
                ]) {
                    if ((input.deviceId != null && token.Device_Id__c == input.deviceId) ||
                        (input.fcmToken != null && input.fcmToken.equals(token.FCM_Token__c))) {
                        token.Active__c = false;
                        contacts.add(token);
                    }
                }
                if (!prospects.isEmpty()) update as system prospects;
                if (!contacts.isEmpty()) update as system contacts;
                reply(200, true, 'Device token deactivated successfully.');
                return;
            }
            Id leadId;
            try {
                leadId = Id.valueOf(input.leadId == null ? null : input.leadId.trim());
                if (leadId.getSObjectType() != Lead.SObjectType) leadId = null;
            } catch (Exception invalidId) {
                leadId = null;
            }
            if (leadId == null || input.deviceId == null || input.fcmToken == null) {
                reply(400, false, 'A valid Lead ID, device ID and FCM token are required.');
                return;
            }
            synchronizeDevices(leadId, new List<TokenRequest>{input});
            reply(200, true, 'Device token saved for all linked projects.');
        } catch (Exception error) {
            Database.rollback(checkpoint);
            System.debug(LoggingLevel.ERROR, 'Prospect token save failed: ' + error.getMessage());
            reply(500, false, 'Unable to save device token.');
        }
    }

    private static void reply(Integer status, Boolean success, String message) {
        RestContext.response.statusCode = status;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(
            new Map<String, Object>{'success' => success, 'message' => message}));
    }

    private static List<Lead> lockFamily(Id leadId) {
        Lead source = [SELECT Id, Portal_Account_Key__c FROM Lead WHERE Id = :leadId LIMIT 1];
        String accountKey = String.isBlank(source.Portal_Account_Key__c)
            ? String.valueOf(source.Id) : source.Portal_Account_Key__c;
        // Serialize registration and project creation on the original account Lead.
        Id rootId = Id.valueOf(accountKey);
        Lead root = [SELECT Id FROM Lead WHERE Id = :rootId LIMIT 1 FOR UPDATE];
        return [SELECT Id, IsConverted, ConvertedContactId FROM Lead
            WHERE Id = :root.Id OR Portal_Account_Key__c = :accountKey];
    }

    // Called after inserting a linked project Lead, in the same transaction.
    public static void copyActiveDevicesToNewProject(Id newLeadId) {
        copyActiveDevices(lockFamily(newLeadId), newLeadId);
    }

    // Resolve existing account devices through the source, without querying the new Lead.
    public static void copyActiveDevicesToNewProject(Id sourceLeadId, Id newLeadId) {
        if (newLeadId == null || newLeadId.getSObjectType() != Lead.SObjectType) {
            throw new TokenAssociationException('Salesforce did not return a valid new Lead ID.');
        }
        copyActiveDevices(lockFamily(sourceLeadId), newLeadId);
    }

    private class TokenAssociationException extends Exception {}

    private static void copyActiveDevices(List<Lead> family, Id newLeadId) {
        Set<Id> leadIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (Lead member : family) {
            leadIds.add(member.Id);
            if (member.ConvertedContactId != null) contactIds.add(member.ConvertedContactId);
        }
        Map<String, TokenRequest> devices = new Map<String, TokenRequest>();
        Map<String, Datetime> seen = new Map<String, Datetime>();
        for (Prospect_Device_Token__c token : [
            SELECT Device_Id__c, FCM_Token__c, Platform__c, App_Version__c, Last_Seen__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c IN :leadIds AND Active__c = true
        ]) {
            rememberDevice(devices, seen, token.Device_Id__c, token.FCM_Token__c,
                token.Platform__c, token.App_Version__c, token.Last_Seen__c);
        }
        for (Mobile_Device_Token__c token : [
            SELECT Device_Id__c, FCM_Token__c, Platform__c, Last_Seen__c
            FROM Mobile_Device_Token__c
            WHERE Contact__c IN :contactIds AND Active__c = true
        ]) {
            rememberDevice(devices, seen, token.Device_Id__c, token.FCM_Token__c,
                token.Platform__c, null, token.Last_Seen__c);
        }
        if (!devices.isEmpty()) synchronizeFamilyDevices(family, devices.values(), newLeadId);
    }

    private static void rememberDevice(Map<String, TokenRequest> devices,
        Map<String, Datetime> seen, String deviceId, String fcmToken,
        String platform, String appVersion, Datetime lastSeen) {
        if (String.isBlank(deviceId) || String.isBlank(fcmToken)) return;
        if (devices.containsKey(deviceId) &&
            (lastSeen == null || (seen.get(deviceId) != null && seen.get(deviceId) >= lastSeen))) return;
        TokenRequest input = new TokenRequest();
        input.deviceId = deviceId;
        input.fcmToken = fcmToken;
        input.platform = platform;
        input.appVersion = appVersion;
        devices.put(deviceId, input);
        seen.put(deviceId, lastSeen);
    }

    private static void synchronizeDevices(Id leadId, List<TokenRequest> inputs) {
        synchronizeFamilyDevices(lockFamily(leadId), inputs, null);
    }

    private static void synchronizeFamilyDevices(List<Lead> family,
        List<TokenRequest> inputs, Id newLeadId) {
        Set<Id> prospectIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (Lead member : family) {
            if (!member.IsConverted) prospectIds.add(member.Id);
            else if (member.ConvertedContactId != null) contactIds.add(member.ConvertedContactId);
        }
        if (newLeadId != null) prospectIds.add(newLeadId);
        Map<String, TokenRequest> devices = new Map<String, TokenRequest>();
        Set<String> fcmTokens = new Set<String>();
        for (TokenRequest input : inputs) {
            devices.put(input.deviceId, input);
            fcmTokens.add(input.fcmToken);
        }
        Set<String> deviceIds = devices.keySet();
        Map<String, Prospect_Device_Token__c> existingProspects = new Map<String, Prospect_Device_Token__c>();
        List<Prospect_Device_Token__c> prospectUpdates = new List<Prospect_Device_Token__c>();
        for (Prospect_Device_Token__c token : [
            SELECT Id, Prospect_Lead__c, Device_Id__c, FCM_Token__c, Active__c
            FROM Prospect_Device_Token__c
            WHERE Device_Id__c IN :deviceIds OR Active__c = true
            ORDER BY Last_Seen__c DESC NULLS LAST, Id ASC
        ]) {
            if (!devices.containsKey(token.Device_Id__c) && !fcmTokens.contains(token.FCM_Token__c)) continue;
            String key = String.valueOf(token.Prospect_Lead__c) + ':' + token.Device_Id__c;
            if (prospectIds.contains(token.Prospect_Lead__c) && devices.containsKey(token.Device_Id__c)
                && !existingProspects.containsKey(key)) {
                existingProspects.put(key, token);
            } else if (token.Active__c) {
                // Remove duplicate rows or associations to a different signed-in account.
                token.Active__c = false;
                prospectUpdates.add(token);
            }
        }
        List<Prospect_Device_Token__c> prospectInserts = new List<Prospect_Device_Token__c>();
        for (Id prospectId : prospectIds) {
            for (TokenRequest input : inputs) {
                String key = String.valueOf(prospectId) + ':' + input.deviceId;
                Prospect_Device_Token__c token = existingProspects.get(key);
                Boolean isNew = token == null;
                if (isNew) token = new Prospect_Device_Token__c(
                    Name = 'Device-' + input.deviceId.left(70), Prospect_Lead__c = prospectId);
                token.Device_Id__c = input.deviceId;
                token.FCM_Token__c = input.fcmToken;
                token.Platform__c = String.isBlank(input.platform) ? 'Android' : input.platform.trim();
                token.App_Version__c = String.isBlank(input.appVersion) ? '1.0.3' : input.appVersion.trim();
                token.Active__c = true;
                token.Last_Seen__c = System.now();
                if (isNew) prospectInserts.add(token);
                else prospectUpdates.add(token);
            }
        }
        Map<String, Mobile_Device_Token__c> existingContacts = new Map<String, Mobile_Device_Token__c>();
        List<Mobile_Device_Token__c> contactUpdates = new List<Mobile_Device_Token__c>();
        for (Mobile_Device_Token__c token : [
            SELECT Id, Contact__c, Device_Id__c, FCM_Token__c, Active__c FROM Mobile_Device_Token__c
            WHERE Device_Id__c IN :deviceIds OR Active__c = true
            ORDER BY Last_Seen__c DESC NULLS LAST, Id ASC
        ]) {
            if (!devices.containsKey(token.Device_Id__c) && !fcmTokens.contains(token.FCM_Token__c)) continue;
            String key = String.valueOf(token.Contact__c) + ':' + token.Device_Id__c;
            if (contactIds.contains(token.Contact__c) && devices.containsKey(token.Device_Id__c)
                && !existingContacts.containsKey(key)) {
                existingContacts.put(key, token);
            } else if (token.Active__c) {
                token.Active__c = false;
                contactUpdates.add(token);
            }
        }
        List<Mobile_Device_Token__c> contactInserts = new List<Mobile_Device_Token__c>();
        for (Id contactId : contactIds) {
            for (TokenRequest input : inputs) {
                Mobile_Device_Token__c token = existingContacts.get(String.valueOf(contactId) + ':' + input.deviceId);
                Boolean isNew = token == null;
                if (isNew) token = new Mobile_Device_Token__c(Contact__c = contactId);
                token.Device_Id__c = input.deviceId;
                token.FCM_Token__c = input.fcmToken;
                token.Platform__c = String.isBlank(input.platform) ? 'Android' : input.platform.trim();
                token.Active__c = true;
                token.Last_Seen__c = System.now();
                if (isNew) contactInserts.add(token);
                else contactUpdates.add(token);
            }
        }
        // All-or-none DML: a failed association must not silently report success.
        if (!prospectUpdates.isEmpty()) update as system prospectUpdates;
        if (!contactUpdates.isEmpty()) update as system contactUpdates;
        if (!prospectInserts.isEmpty()) insert as system prospectInserts;
        if (!contactInserts.isEmpty()) insert as system contactInserts;
    }
}