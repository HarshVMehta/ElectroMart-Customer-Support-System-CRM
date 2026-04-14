public class CaseTriggerHandler {

    public static void assignCases(List<Case> caseList) {
        CaseService.assignQueue(caseList);
    }

    public static void sendEmailToCaseAcknowledgements(List<Case> caseList) {
        CaseService.sendEmailToCaseAcknowledgements(caseList);
    }
}