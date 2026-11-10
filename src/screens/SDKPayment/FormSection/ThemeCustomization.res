@react.component
let make = (~getClientSecret) => {
  open FormRenderer
  open SDKPaymentUtils
  open SDKPaymentHelper

  let {
    sdkThemeInitialValues,
    setSdkThemeInitialValues,
    setKeyForReRenderingSDK,
    initialValuesForCheckoutForm,
    showBillingAddress,
    isGuestMode,
  } = React.useContext(SDKProvider.defaultContext)
  let showToast = ToastAdapter.useShowToast()

  let onSubmit = async (values, _) => {
    try {
      let typedValues = getTypedPaymentData(
        {initialValuesForCheckoutForm->Identity.genericTypeToJson},
        ~onlyEssential=true,
        ~showBillingAddress,
        ~isGuestMode,
      )
      let _ = await getClientSecret(~typedValues)
    } catch {
    | _ => showToast(~message="Something went wrong. Please try again", ~toastType=ToastError)
    }
    setSdkThemeInitialValues(_ => values)
    setKeyForReRenderingSDK(_ => Date.now()->Float.toString)
    Nullable.null
  }

  let paymentConnectorList = ConnectorListInterface.useFilteredConnectorList(
    ~retainInList=PaymentProcessor,
  )

  <Form formClass="mt-5" initialValues=sdkThemeInitialValues onSubmit>
    <FieldRenderer field=selectThemeField fieldWrapperClass="!w-full" />
    <FieldRenderer field=selectLocaleField fieldWrapperClass="!w-full" />
    <FieldRenderer field=selectLayoutField fieldWrapperClass="!w-full" />
    <FieldRenderer field=selectLabelsField fieldWrapperClass="!w-full" />
    <FieldRenderer field={enterPrimaryColorValue("#006DF9")} fieldWrapperClass="!w-full" />
    <SubmitButton
      text="Show preview"
      disabledParameter={paymentConnectorList->Array.length === 0}
      customSubmitButtonStyle="!mt-5 !w-full"
    />
  </Form>
}
