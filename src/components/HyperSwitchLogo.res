@react.component
let make = (
  ~logoClass="",
  ~handleClick=?,
  ~logoVariant=CommonAuthTypes.IconWithText,
  ~logoHeight="h-6",
  ~iconUrl=None,
) => {
  let {theme} = React.useContext(ThemeProvider.themeContext)
  let iconFolder = switch theme {
  | Dark => "Dark"
  | Light => "Light"
  }

  let handleClickEvent = ev => {
    switch handleClick {
    | Some(fn) => fn(ev)
    | None => ()
    }
  }

  // Pinnacle: no Juspay/Hyperswitch logo on the sign-in pages. Only a theme's
  // own logo (IconWithURL) is shown, and nothing when there is none.
  let iconImagePath = switch logoVariant {
  | Icon => `/assets/${iconFolder}/hyperswitchLogoIcon.svg`
  | Text => `/assets/${iconFolder}/hyperswitchLogoText.svg`
  | IconWithText => ""
  | IconWithURL => `${iconUrl->Option.getOr("")}`
  }

  <RenderIf condition={iconImagePath->LogicUtils.isNonEmptyString}>
    <div className={`${logoClass}`} onClick={handleClickEvent}>
      <img alt="image" src=iconImagePath className=logoHeight />
    </div>
  </RenderIf>
}
