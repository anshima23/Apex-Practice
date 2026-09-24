trigger BookingTrigger on Booking__c (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            BookingTriggerHandler.handleBeforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            BookingTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            BookingTriggerHandler.handleBeforeDelete(Trigger.old);
        }
    } else if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            BookingTriggerHandler.handleAfterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            BookingTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            // FIX: Pass Trigger.oldMap instead of Trigger.old
            BookingTriggerHandler.handleAfterDelete(Trigger.oldMap);
        } else if (Trigger.isUndelete) {
            BookingTriggerHandler.handleAfterUndelete(Trigger.new);
        }
    }
}