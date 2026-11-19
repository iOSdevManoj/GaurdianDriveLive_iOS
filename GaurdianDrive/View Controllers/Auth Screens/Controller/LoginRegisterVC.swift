//
//  LoginRegisterVC.swift
//  GaurdianDrive
//
//  Created by KETAN on 12/12/25.
//

import UIKit
import CountryPickerView
import GoogleSignIn
import FirebaseCore
import AuthenticationServices
import SwiftQRScanner

class LoginRegisterVC: UIViewController {

    //Reference Outlets..
    @IBOutlet var imgBg: UIImageView!
    @IBOutlet var txtEmail: UITextField!
    @IBOutlet var txtMobile: UITextField!
    @IBOutlet var lblEmail: UILabel!
    @IBOutlet var lblPhone: UILabel!
    @IBOutlet var lblMainTitle: UILabel!
    @IBOutlet var lblSubTitle: UILabel!
    @IBOutlet var lblLoginNowLabel: UILabel!
    @IBOutlet var viewForTerms: UIView!
    @IBOutlet var viewForPolicy: UIView!
    @IBOutlet var btnLoginNow: UIButton!
    @IBOutlet var viewForPhone: UIView!
    @IBOutlet var viewForEmail: UIView!
    @IBOutlet var lblCountryCode: UILabel!
    @IBOutlet var imgCountryFlag: UIImageView!
    @IBOutlet var viewForRegisterNow: UIView!
    @IBOutlet var controlForGmail: UIControl!
    @IBOutlet var controlForApple: UIControl!
    @IBOutlet var viewForORPart: UIView!
    @IBOutlet var btnLoginWithQR: UIButton!
// new Outlet
    @IBOutlet var btnForTerm: UIButton!
    @IBOutlet var btnForOneTimePass: UIButton!
    @IBOutlet var lblForOneTimePass: UILabel!
    @IBOutlet var LblForOneTimePassNote: UILabel!
    @IBOutlet var btnContinue: UIButton!
    
    @IBOutlet var onetimeViewHeight: NSLayoutConstraint!
    @IBOutlet var viewForOneTimePass: UIView!
    @IBOutlet var oneRegisterViewHeight: NSLayoutConstraint!

    //Variables...
    var isForLogin = false
    var isForEmail = true
    let countryPickerView = CountryPickerView()

    override func viewDidLoad() {
        super.viewDidLoad()

        self.initialisation() // Basic intialisation...
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationItem.setHidesBackButton(true, animated: true)
        self.navigationController?.setNavigationBarHidden(true, animated: false)
        if isForEmail {
            onetimeViewHeight.constant = 0
            viewForOneTimePass.alpha = 0
        }else {
            onetimeViewHeight.constant = 76.5
            viewForOneTimePass.alpha = 1
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.txtEmail.text = ""
    }
}

//MARK: - Initialisation functions...
extension LoginRegisterVC
{
    func initialisation()
    {
        // Hide background image as we are using solid colors now
        if self.isForLogin
        {
//            self.view.backgroundColor = .white
            self.imgBg.image = UIImage(named: "img_white_bg")
            let loginType = (appDelegate.isFromParent) ? "Parent" : "Children"
            self.lblMainTitle.text = "Login \(loginType)"
            self.lblSubTitle.text = "Enter below details to continue."
            self.viewForTerms.isHidden = true
            self.viewForPolicy.isHidden = true
            self.viewForOneTimePass.isHidden = true
            self.btnLoginNow.setTitle(" Register Now", for: .normal)
            self.lblLoginNowLabel.text = "Don’t have an account? "
            
            if !appDelegate.isFromParent
            {
                self.viewForRegisterNow.isHidden = true
                self.controlForGmail.isHidden = true
                self.controlForApple.isHidden = true
//                self.viewForORPart.isHidden = true
                self.btnLoginWithQR.isHidden = false
            }
        } else {
//            self.view.backgroundColor = hexStringToUIColor(hex: "#FFF7ED")
            self.imgBg.image = UIImage(named: "img_brige_bg")
            self.viewForTerms.isHidden = false
            self.viewForPolicy.isHidden = false
            self.viewForOneTimePass.isHidden = false
        }
        
        if #available(iOS 15.0, *) {
            self.btnForOneTimePass.configuration = nil
            self.btnForTerm.configuration = nil
        }
        
        let unselectedImg = UIImage(named: "Checkbox")?.withRenderingMode(.alwaysOriginal)
        let selectedImg = UIImage(named: "checkbox_Fill")?.withRenderingMode(.alwaysOriginal)
        
        self.btnForOneTimePass.setImage(unselectedImg, for: .normal)
        self.btnForOneTimePass.setImage(selectedImg, for: .selected)
        self.btnForOneTimePass.removeTarget(nil, action: nil, for: .touchUpInside)
        self.btnForOneTimePass.addTarget(self, action: #selector(tapToOneTimePassBox), for: .touchUpInside)
        
        self.btnForTerm.setImage(unselectedImg, for: .normal)
        self.btnForTerm.setImage(selectedImg, for: .selected)
        self.btnForTerm.removeTarget(nil, action: nil, for: .touchUpInside)
        self.btnForTerm.addTarget(self, action: #selector(tapToTermsBox), for: .touchUpInside)
        
        self.initialisCountyCodeView()
    }
    
    //MARK: - Country code initialisation..
    func initialisCountyCodeView()
    {
        //let country = countryPickerView.selectedCountry
        countryPickerView.delegate = self
        countryPickerView.dataSource = self
        countryPickerView.showCountryCodeInView = false
        countryPickerView.tintColor = UIColor.black
        countryPickerView.setCountryByCode("US")
        // self.txtCountryCode.text = country.phoneCode
        if let country = countryPickerView.getCountryByCode("US") {
            self.imgCountryFlag.image = country.flag
        }
    }
}

//MARK: - Click Events.....
extension LoginRegisterVC
{
    @IBAction func tapToBack(_ sender: UIControl) {
        self.navigationController?.popViewController(animated: true)
    }
    @IBAction func tapToEmail(_ sender: UIControl) {
        isForEmail = true
        if isForLogin && !isForEmail{
            oneRegisterViewHeight.constant = -27.0
        }
        else {
            oneRegisterViewHeight.constant = 50.0
        }

        if isForEmail {
            onetimeViewHeight.constant = 0
            viewForOneTimePass.alpha = 0
        }else {
            onetimeViewHeight.constant = 76.5
            viewForOneTimePass.alpha = 1

        }
        DispatchQueue.main.async {
            self.setPhoneOrEmailUIData(isFromEmail: true)
        }
    }
    @IBAction func tapToPhone(_ sender: UIControl) {
        isForEmail = false
        if isForLogin && !isForEmail{
            oneRegisterViewHeight.constant = -27.0
        }
        else {
            oneRegisterViewHeight.constant = 50.0
        }
        if isForEmail {
            onetimeViewHeight.constant = 0
            viewForOneTimePass.alpha = 0
        }else {
            onetimeViewHeight.constant = 76.5
            viewForOneTimePass.alpha = 1

        }
        DispatchQueue.main.async {
            self.setPhoneOrEmailUIData(isFromEmail: self.isForEmail)
        }
    }
    @IBAction func tapToCountryCode(_ sender: UIControl) {
        countryPickerView.showCountriesList(from: self)
    }
    @IBAction func tapToContinue(_ sender: UIButton) {
        self.view.endEditing(true)
        if self.isValidData()
        {
            if self.isForLogin
            {
                appDelegate.showHud()
                self.apiCallForLogin()
            }else{
                appDelegate.showHud()
                self.apiCallForLoginRegister()
            }
        }
    }
    @IBAction func tapToLoginWithQR(_ sender: UIButton) {
        var configuration = QRScannerConfiguration()
        
        configuration.cancelButtonTitle = "Cancel"
        configuration.cancelButtonTintColor =  UIColor(named: "AppDarkBlue")
//        configuration.cancelButtonBackgroundColor = UIColor(named: "AppDarkBlue") ?? .systemBlue

        
        let scanner = QRCodeScannerController(qrScannerConfiguration: configuration)
        scanner.delegate = self
        self.present(scanner, animated: true, completion: nil)
    }
    @IBAction func tapToGoogle(_ sender: UIControl) {
        self.view.endEditing(true)
        
//        if GIDSignIn.sharedInstance.currentUser != nil {
//            GIDSignIn.sharedInstance.signOut()
//        }
        
        guard let clientID = FirebaseApp.app()?.options.clientID else { return }
        
        // Create Google Sign In configuration object.
        let config = GIDConfiguration(clientID: clientID)
        
        GIDSignIn.sharedInstance.configuration = config
        
        GIDSignIn.sharedInstance.signIn(withPresenting: self) { signInResult, error in
            guard error == nil else { return }
            
//            print(signInResult)
//            print(signInResult?.user.profile?.name)
//            print(signInResult?.user.profile?.email)
//            print(signInResult?.user.profile?.imageURL(withDimension: 100))
//            print(signInResult?.user.fetcherAuthorizer.userEmail)
//            print(signInResult?.user.userID)
            GIDSignIn.sharedInstance.signOut()
            
            if self.isForLogin
            {
                DispatchQueue.main.async {
                    appDelegate.showHud()
                    self.apiCallForSocialLogin(aSocialToken:(signInResult?.user.userID)!, aSocialType: "GOOGLE")
                }
            }else {
                let param = ["email":(signInResult?.user.profile!.email)!, "name":(signInResult?.user.profile!.name)!, "socialToken":(signInResult?.user.userID)!, "socialType":"GOOGLE"] as [String : Any]
                self.navigateToBasicInfoWithSocialData(aDictData: param)
            }
        }
    }
    @IBAction func tapToApple(_ sender: UIControl) {
        if #available(iOS 13.0, *) {
            let authorizationProvider = ASAuthorizationAppleIDProvider()
            let request = authorizationProvider.createRequest()
            request.requestedScopes = [.email,.fullName]
            let authorizationController = ASAuthorizationController(authorizationRequests: [request])
            authorizationController.delegate = self
            authorizationController.presentationContextProvider = self
            authorizationController.performRequests()
        } else {
            // Fallback on earlier versions
        }
    }
    @IBAction func tapToTermsCondition(_ sender: UIButton) {
        let objWebViewCommonVC = storyBoards.Settings.instantiateViewController(withIdentifier:"WebViewCommonVC" ) as! WebViewCommonVC
        objWebViewCommonVC.strTitle = "Terms Of Services"
        self.navigationController?.pushViewController(objWebViewCommonVC, animated: true)
    }
    @IBAction func tapToPolicy(_ sender: UIButton) {
        let objWebViewCommonVC = storyBoards.Settings.instantiateViewController(withIdentifier:"WebViewCommonVC" ) as! WebViewCommonVC
        objWebViewCommonVC.strTitle = "Privacy Policy"
        self.navigationController?.pushViewController(objWebViewCommonVC, animated: true)
    }
    @IBAction func tapToLoginNow(_ sender: UIButton) {
        if self.isForLogin
        {
            let objLoginRegisterVC = storyBoards.Main.instantiateViewController(withIdentifier: "LoginRegisterVC") as! LoginRegisterVC
            objLoginRegisterVC.isForLogin = false
            self.navigationController?.pushViewController(objLoginRegisterVC, animated: true)
        }else{
            self.navigationController?.popViewController(animated: true)
        }
    }
    
    @objc func tapToOneTimePassBox() {
        self.btnForOneTimePass.isSelected.toggle()
    }
    
    @objc func tapToTermsBox() {
        self.btnForTerm.isSelected.toggle()
    }
    
    //Email / Phone UI setup.....
    func setPhoneOrEmailUIData(isFromEmail:Bool)
    {
        self.isForEmail = isFromEmail
        self.lblPhone.isHidden = isFromEmail
        self.lblEmail.isHidden = !isFromEmail
        self.viewForPhone.isHidden = isFromEmail
        self.viewForEmail.isHidden = !isFromEmail
        
        self.btnForOneTimePass.isSelected = false
        self.btnForTerm.isSelected = false
        
        if !self.isForLogin {
            // When Email is selected, show Terms/Policy. When Phone is selected, hide them.
           // self.viewForTerms.isHidden = !isFromEmail
           // self.viewForPolicy.isHidden = !isFromEmail
            
            // Show OTP checkbox only when Phone is selected
//            self.viewForOneTimePass.isHidden = isFromEmail
            
            self.LblForOneTimePassNote.text = "By continuing, you agree to receive SMS messages from Guardian Drive for one-time passcodes related to your login. Message frequency varies. Message and data rates may apply. Reply STOP to opt out, HELP for help."
        }
    }
    
    func navigateToBasicInfoWithSocialData(aDictData:[String:Any])
    {
        let objBasicInfoVC = storyBoards.Main.instantiateViewController(withIdentifier: "BasicInfoVC") as! BasicInfoVC
        objBasicInfoVC.isFromSocial = true
        objBasicInfoVC.dictUserDetails = aDictData
        objBasicInfoVC.isForEmail = true
        self.navigationController?.pushViewController(objBasicInfoVC, animated: true)
    }
}

//MARK: - Scan QR code delegates..
extension LoginRegisterVC: QRScannerCodeDelegate {
    func qrScanner(_ controller: UIViewController, didFailWithError error: SwiftQRScanner.QRCodeError) {
        print("error:\(error.localizedDescription)")
        controller.dismiss(animated: true)
    }
    
    func qrScannerDidFail(_ controller: UIViewController, error: QRCodeError) {
        print("error:\(error.localizedDescription)")
        controller.dismiss(animated: true)
    }
    
    func qrScanner(_ controller: UIViewController, didScanQRCodeWithResult result: String) {
        print("result:\(result)")
        appDelegate.showHud()
        self.apiCallForSendQRCode(strQRCodeResult: result)
        controller.dismiss(animated: true)
    }
    
    func qrScannerDidCancel(_ controller: UIViewController) {
        print("SwiftQRScanner did cancel")
        controller.dismiss(animated: true)
    }
}

//MARK: - ASAuthorizationControllerDelegate
extension LoginRegisterVC: ASAuthorizationControllerDelegate {
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }
        var name = createString(value: appleIDCredential.fullName?.givenName as AnyObject) + " \(createString(value: appleIDCredential.fullName?.familyName as AnyObject))"
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var email = createString(value: appleIDCredential.email as AnyObject).trimmingCharacters(in: .whitespacesAndNewlines)
        
        if name.isEmpty
        {
            if UserDefaults.Main.string(forKey:.appleIDName) != ""
            {
                name = UserDefaults.Main.string(forKey:.appleIDName)
            }
        }else{
            UserDefaults.Main.set(name, forKey: .appleIDName)
        }
        
        if email.isEmpty
        {
            if UserDefaults.Main.string(forKey:.appleID) != ""
            {
                email = UserDefaults.Main.string(forKey:.appleID)
            }
        } else {
            // Keep the exact email Apple returns, including private relay addresses.
            UserDefaults.Main.set(email, forKey: .appleID)
        }
        
        if self.isForLogin
        {
            appDelegate.showHud()
            self.apiCallForSocialLogin(aSocialToken: appleIDCredential.user, aSocialType: "APPLE")
        }else {
            let param = ["email":email, "name":name, "socialToken":appleIDCredential.user, "socialType":"APPLE"] as [String : Any]
            self.navigateToBasicInfoWithSocialData(aDictData: param)
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("AppleID Credential failed with error: \(error.localizedDescription)")
        //        self.popupAlert(title: "AppleID Credential failed", message:"AppleID Credential failed with error: \(error.localizedDescription)", actionTitles: ["OK"], actions:[nil])
    }
}

//MARK: - ASAuthorizationControllerPresentationContextProviding
@available(iOS 13.0, *)
extension LoginRegisterVC: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return self.view.window!
    }
}

//MARK: - Country Pickerview Delegates and Datasources
extension LoginRegisterVC : CountryPickerViewDelegate, CountryPickerViewDataSource
{
    func countryPickerView(_ countryPickerView: CountryPickerView, didSelectCountry country: Country) {
        self.lblCountryCode.text = country.phoneCode
        self.imgCountryFlag.image = country.flag
    }
    func navigationTitle(in countryPickerView: CountryPickerView) -> String?
    {
        return "Country Code"
    }
    
    func showPhoneCodeInList(in countryPickerView: CountryPickerView) -> Bool
    {
        return true
    }
}

//MARK: - Textfield delegates...
extension LoginRegisterVC : UITextFieldDelegate
{
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        //Try to find next responder
        textField.resignFirstResponder()
        return false
    }
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        self.viewForEmail.layer.borderColor = UIColor(named:"AppBorderGray")?.cgColor
        self.viewForPhone.layer.borderColor = UIColor(named:"AppBorderGray")?.cgColor
        return true
    }

    //MARK: - Validation Method
    func isValidData() -> Bool{
        if self.isForEmail
        {
            if !(self.txtEmail.text!.isStringWithoutSpace()){
                appDelegate.window?.rootViewController?.view.makeToast("Please enter email")
                self.viewForEmail.layer.borderColor = UIColor(named:"AppRed")?.cgColor
                return false;
            }
            else if !(txtEmail?.text!.isValidEmail)!{
                appDelegate.window?.rootViewController?.view.makeToast("Please enter valid email id")
                self.viewForEmail.layer.borderColor = UIColor(named:"AppRed")?.cgColor
                return false;
            }
        }else{
            if !(self.txtMobile.text!.isStringWithoutSpace()){
                appDelegate.window?.rootViewController?.view.makeToast("Please enter phone number")
                self.viewForPhone.layer.borderColor = UIColor(named:"AppRed")?.cgColor
                return false;
            }
            else if self.txtMobile.text!.count != 10
            {
                appDelegate.window?.rootViewController?.view.makeToast("Please enter valid phone number")
                self.viewForPhone.layer.borderColor = UIColor(named:"AppRed")?.cgColor
                return false;
            }
            else {
                let phone = self.txtMobile.text!
                let code = self.lblCountryCode.text!
                let firstChar = phone.first ?? "0"
                
                if code == "+91" && !["6", "7", "8", "9"].contains(firstChar) {
                    appDelegate.window?.rootViewController?.view.makeToast("Please enter a valid Indian mobile number")
                    self.viewForPhone.layer.borderColor = UIColor(named:"AppRed")?.cgColor
                    return false
                } else if code == "+1" && ["0", "1"].contains(firstChar) {
                    appDelegate.window?.rootViewController?.view.makeToast("Please enter a valid US mobile number")
                    self.viewForPhone.layer.borderColor = UIColor(named:"AppRed")?.cgColor
                    return false
                }
            }
        }
        
        if !self.isForLogin {
            if self.isForEmail {
                if !self.btnForTerm.isSelected {
                    appDelegate.window?.rootViewController?.view.makeToast("Please agree to our Terms and Conditions and Privacy Policy to continue")
                    return false
                }
            } else {
                if !self.btnForOneTimePass.isSelected {
                    appDelegate.window?.rootViewController?.view.makeToast("Please agree to receive a one-time passcode to continue")
                    return false
                }
                if !self.btnForOneTimePass.isSelected {
                    appDelegate.window?.rootViewController?.view.makeToast("Please agree to receive a one-time passcode to continue")
                    return false
                }
                if !self.btnForTerm.isSelected {
                    appDelegate.window?.rootViewController?.view.makeToast("Please agree to our Terms and Conditions and Privacy Policy to continue")
                    return false
                }
            }
        }
        return true
    }
    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        if !self.isForEmail
        {
            // Allow only numbers
            let allowedCharacters = CharacterSet.decimalDigits
            let characterSet = CharacterSet(charactersIn: string)
            
            if !allowedCharacters.isSuperset(of: characterSet) {
                return false
            }
            
            // Get updated text
            let currentText = textField.text ?? ""
            guard let stringRange = Range(range, in: currentText) else {
                return false
            }
            
            let updatedText = currentText.replacingCharacters(in: stringRange, with: string)
            
            // Limit to 10 digits
            return updatedText.count <= 10
        }
        return true
    }
}

//MARK: - Api callings...
extension LoginRegisterVC
{
    //MARK: - Login/Register user...
    func apiCallForLoginRegister()
    {
        //let fcmToken = UserDefaults.Main.string(forKey: .deviceToken)
        var param = [String : Any]()
        var webUrl = ""
        
        if self.isForEmail
        {
            webUrl = appDelegate.isFromParent
                ? WebURL.sendRegisterEmailCode
                : WebURL.sendChildRegisterEmailCode
            
            param = ["email":self.txtEmail.text!.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] as [String : Any]
        }else{
            webUrl = appDelegate.isFromParent
                ? WebURL.sendRegisterPhoneCode
            : WebURL.sendChildRegisterPhoneCode
            
            param = ["mobileNo":self.txtMobile.text!.trimmingCharacters(in: .whitespacesAndNewlines),"countryCode":self.lblCountryCode.text!.trimmingCharacters(in: .whitespacesAndNewlines)] as [String : Any]
        }
        
        apiCallViewModel.postApiCallWithDisctionaryResponse(aUrl: webUrl, param:param) { (isSuccess, responseDict,statusCode) in
            
            appDelegate.hideHud()
            
            if isSuccess
            {
                let objOTPVC = storyBoards.Main.instantiateViewController(withIdentifier: "OTPVC") as! OTPVC
                objOTPVC.isFromLogin = self.isForLogin
                objOTPVC.isEmail = self.isForEmail
                objOTPVC.strEmailPhone = self.isForEmail ? self.txtEmail.text!.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : self.txtMobile.text!.trimmingCharacters(in: .whitespacesAndNewlines)
                objOTPVC.strCountyCode = self.lblCountryCode.text!
                self.navigationController?.pushViewController(objOTPVC, animated: true)
            }else {
                let strMessage = getStringFromDictionary(dictionary: responseDict, key: "defaultMessage")
                appDelegate.window?.rootViewController?.view.makeToast(strMessage)
                if self.isForEmail
                {
                    self.viewForEmail.layer.borderColor = UIColor(named:"AppRed")?.cgColor

                }else{
                    self.viewForPhone.layer.borderColor = UIColor(named:"AppRed")?.cgColor
                }
            }
        }
    }
    
    //MARK: - Login/Register user...
    func apiCallForLogin()
    {
        //let fcmToken = UserDefaults.Main.string(forKey: .deviceToken)
        var param = [String : Any]()
        var webUrl = ""
        let strType = appDelegate.isFromParent ? "PARENT" : "CHILD"
        
        if self.isForEmail
        {
            webUrl = WebURL.loginWithEmail
            param = ["email":self.txtEmail.text!.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),"type":strType] as [String : Any]
        }else{
            webUrl = WebURL.loginWithPhone
            param = ["mobileNo":self.txtMobile.text!.trimmingCharacters(in: .whitespacesAndNewlines),"countryCode":self.lblCountryCode.text!.trimmingCharacters(in: .whitespacesAndNewlines),"type":strType] as [String : Any]
        }
        
        apiCallViewModel.postApiCallWithDisctionaryResponse(aUrl: webUrl, param:param) { (isSuccess, responseDict,statusCode) in
            
            appDelegate.hideHud()
            
            if isSuccess
            {
                let objOTPVC = storyBoards.Main.instantiateViewController(withIdentifier: "OTPVC") as! OTPVC
                objOTPVC.isFromLogin = self.isForLogin
                objOTPVC.isEmail = self.isForEmail
                objOTPVC.strEmailPhone = self.isForEmail ? self.txtEmail.text!.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : self.txtMobile.text!.trimmingCharacters(in: .whitespacesAndNewlines)
                objOTPVC.strCountyCode = self.lblCountryCode.text!
                self.navigationController?.pushViewController(objOTPVC, animated: true)
            }else {
                let strMessage = getStringFromDictionary(dictionary: responseDict, key: "defaultMessage")
                appDelegate.window?.rootViewController?.view.makeToast(strMessage)
                if self.isForEmail
                {
                    self.viewForEmail.layer.borderColor = UIColor(named:"AppRed")?.cgColor

                }else{
                    self.viewForPhone.layer.borderColor = UIColor(named:"AppRed")?.cgColor
                }
            }
        }
    }
    
    //MARK: - Social Login/Register user...
    func apiCallForSocialLogin(aSocialToken:String,aSocialType:String)
    {
        //let fcmToken = UserDefaults.Main.string(forKey: .deviceToken)
        let param = ["socialToken":aSocialToken,"socialType":aSocialType,"timeZoneOffset":getTimeZoneOffsetMinutes()] as [String : Any]
        
        apiCallViewModel.postApiCallWithDisctionaryResponse(aUrl: WebURL.socialLogin, param:param) { (isSuccess, responseDict,statusCode) in
            
            appDelegate.hideHud()
            
            if isSuccess
            {
                
                setLoginUserData(dicResult: responseDict,isFromProfile: false)
                UserDefaults.Main.set(true, forKey: .autoLogin)

                if appDelegate.isFromParent
                {
                    UserDefaults.Main.set(true, forKey: .isParent)
                    appDelegate.setRootController()
                }else{
                    UserDefaults.Main.set(false, forKey: .isParent)
                    let objChildHomeVC = storyBoards.Child.instantiateViewController(withIdentifier: "ChildHomeVC") as! ChildHomeVC
                    self.navigationController?.pushViewController(objChildHomeVC, animated: true)
                }
            }else {
                let strMessage = getStringFromDictionary(dictionary: responseDict, key: "defaultMessage")
                appDelegate.window?.rootViewController?.view.makeToast(strMessage)
            }
        }
    }
    
    //MARK: - Social Login/Register user...
    func apiCallForSendQRCode(strQRCodeResult:String)
    {
        //let fcmToken = UserDefaults.Main.string(forKey: .deviceToken)
        let param = ["qrCode":strQRCodeResult] as [String : Any]
        
        apiCallViewModel.postApiCallWithDisctionaryResponse(aUrl: WebURL.sendQRCodeData, param:param) { (isSuccess, responseDict,statusCode) in
            
            appDelegate.hideHud()
            
            if isSuccess
            {
                let objOTPVC = storyBoards.Main.instantiateViewController(withIdentifier: "OTPVC") as! OTPVC
                objOTPVC.isFromQR = true
                objOTPVC.strQRData = strQRCodeResult
                self.navigationController?.pushViewController(objOTPVC, animated: true)
            }else {
                let strMessage = getStringFromDictionary(dictionary: responseDict, key: "defaultMessage")
                appDelegate.window?.rootViewController?.view.makeToast(strMessage)
            }
        }
    }
}
