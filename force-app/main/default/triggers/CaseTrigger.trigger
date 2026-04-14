trigger CaseTrigger on Case (before insert, before update, after insert) {

    if (Trigger.isBefore) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            CaseTriggerHandler.assignCases(Trigger.new);
        }
    }

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            CaseTriggerHandler.sendEmailToCaseAcknowledgements(Trigger.new);
        }
    }
}