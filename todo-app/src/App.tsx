import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import { Trash2 } from 'lucide-react'

interface Todo {
  id: string;
  text: string;
  completed: boolean;
}

function App() {
  const [todos, setTodos] = useState<Todo[]>([])
  const [inputValue, setInputValue] = useState('')

  const addTodo = (e: React.FormEvent) => {
    e.preventDefault()
    if (!inputValue.trim()) return
    const newTodo: Todo = {
      id: crypto.randomUUID(),
      text: inputValue.trim(),
      completed: false
    }
    setTodos([...todos, newTodo])
    setInputValue('')
  }

  const toggleTodo = (id: string) => {
    setTodos(todos.map(todo =>
      todo.id === id ? { ...todo, completed: !todo.completed } : todo
    ))
  }

  const deleteTodo = (id: string) => {
    setTodos(todos.filter(todo => todo.id !== id))
  }

  return (
    <div className="min-h-screen bg-slate-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-md shadow-xl border-0">
        <CardHeader className="bg-slate-900 text-white rounded-t-xl">
          <CardTitle className="text-2xl text-center font-bold">Todo List</CardTitle>
        </CardHeader>
        <CardContent className="p-6">
          <form onSubmit={addTodo} className="flex gap-2 mb-6">
            <Input
              type="text"
              placeholder="What needs to be done?"
              value={inputValue}
              onChange={(e) => setInputValue(e.target.value)}
              className="flex-1"
            />
            <Button type="submit">Add</Button>
          </form>

          <div className="space-y-3">
            {todos.length === 0 ? (
              <p className="text-center text-slate-500 py-4">No tasks yet. Add one above!</p>
            ) : (
              todos.map(todo => (
                <div 
                  key={todo.id} 
                  className="flex items-center justify-between p-3 border rounded-lg bg-white shadow-sm transition-all hover:shadow-md"
                >
                  <div className="flex items-center gap-3">
                    <Checkbox 
                      checked={todo.completed} 
                      onCheckedChange={() => toggleTodo(todo.id)}
                      id={todo.id}
                    />
                    <label 
                      htmlFor={todo.id}
                      className={`text-sm font-medium leading-none cursor-pointer ${todo.completed ? 'line-through text-slate-400' : 'text-slate-700'}`}
                    >
                      {todo.text}
                    </label>
                  </div>
                  <Button 
                    variant="ghost" 
                    size="icon" 
                    onClick={() => deleteTodo(todo.id)}
                    className="text-red-500 hover:text-red-700 hover:bg-red-50"
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </div>
              ))
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

export default App
