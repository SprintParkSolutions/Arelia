trigger AreliaFileUploadNotificationTrigger on ContentDocumentLink (after insert) {
   AreliaFileUploadNotificationHandler.handleAfterInsert(Trigger.new);
}