trigger CreateTaskOnVendorAssignment on Vendor_Assignment__c (after insert) {
    List<Task> tasksToCreate = new List<Task>();
    Map<Id, Vendor__c> vendorMap = new Map<Id, Vendor__c>();

    // Collect Vendor Ids
    for (Vendor_Assignment__c assignment : Trigger.new) {
        if (assignment.Vendor__c != null) {
            vendorMap.put(assignment.Vendor__c, null);
        }
    }

    // Query vendor emails
    vendorMap.putAll([
        SELECT Id, Name, Email__c FROM Vendor__c
        WHERE Id IN :vendorMap.keySet()
    ]);

    List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();

    for (Vendor_Assignment__c assignment : Trigger.new) {
        if (assignment.Vendor__c != null && vendorMap.containsKey(assignment.Vendor__c)) {
            Vendor__c vendor = vendorMap.get(assignment.Vendor__c);

            // Create Task
            Task t = new Task();
            t.Subject = 'New Vendor Assignment Created';
            t.Description = 'Details of assignment: ' + assignment.Name;
            t.Status = 'Not Started';
            t.Priority = 'Normal';
            t.OwnerId = UserInfo.getUserId();
            t.WhatId = assignment.Vendor__c;
            tasksToCreate.add(t);

            // Send Email
            if (vendor.Email__c != null) {
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new String[] { vendor.Email__c });
                mail.setSubject('You have a new assignment');
                mail.setPlainTextBody(
                    'Hello ' + vendor.Name + ',\n\n' +
                    'A new assignment has been created for you: ' + assignment.Name + '\n\n' +
                    'Please check your account for more details.'
                );
                emailsToSend.add(mail);
            }
        }
    }

    if (!tasksToCreate.isEmpty()) {
        try {
            insert tasksToCreate;
        } catch (DmlException e) {
            System.debug('Task Insert Error: ' + e.getMessage());
        }
    }

    if (!emailsToSend.isEmpty()) {
        try {
            Messaging.sendEmail(emailsToSend);
        } catch (Exception e) {
            System.debug('Email Error: ' + e.getMessage());
        }
    }
}