import TodoPage from './pages/TodoPage'
import LoginPanel from './ui/LoginPanel'

export default function App() {
  return (
    <div className="container">
      <header className="header">
        <div>
          <h1>Todo CRUD (API v1)</h1>
          <div className="muted small">Google Sign-In → app JWT → Bearer calls</div>
        </div>
        <div className="spacer" />
        <LoginPanel />
      </header>
      <TodoPage />
    </div>
  )
}
